import gradio as gr
import os
import sys
import time
import tempfile
import shutil
from typing import Any, Union, List, Tuple

import numpy as np
import torch
import trimesh
from huggingface_hub import snapshot_download
from PIL import Image
from accelerate.utils import set_seed

# Add the project root to Python path
sys.path.insert(0, os.path.dirname(__file__))

from src.utils.data_utils import get_colored_mesh_composition
from src.utils.render_utils import render_views_around_mesh, render_normal_views_around_mesh, make_grid_for_images_or_videos, export_renderings
from src.pipelines.pipeline_partcrafter import PartCrafterPipeline
from src.utils.image_utils import prepare_image
from src.models.briarmbg import BriaRMBG

# Global variables for models
pipe = None
rmbg_net = None

# ROCm compatibility fixes
if torch.cuda.is_available():
    device = "cuda"
    torch.cuda.empty_cache()
    if hasattr(torch.cuda, 'set_per_process_memory_fraction'):
        torch.cuda.set_per_process_memory_fraction(0.8)
else:
    device = "cpu"

dtype = torch.float16
MAX_NUM_PARTS = 16

def load_models():
    global pipe, rmbg_net
    
    if pipe is not None and rmbg_net is not None:
        return
    
    # Download pretrained weights
    partcrafter_weights_dir = "pretrained_weights/PartCrafter"
    rmbg_weights_dir = "pretrained_weights/RMBG-1.4"
    
    if not os.path.exists(partcrafter_weights_dir):
        snapshot_download(repo_id="wgsxm/PartCrafter", local_dir=partcrafter_weights_dir)
    if not os.path.exists(rmbg_weights_dir):
        snapshot_download(repo_id="briaai/RMBG-1.4", local_dir=rmbg_weights_dir)
    
    # Load RMBG model
    rmbg_net = BriaRMBG.from_pretrained(rmbg_weights_dir).to(device)
    rmbg_net.eval()
    
    # Load PartCrafter pipeline
    pipe = PartCrafterPipeline.from_pretrained(partcrafter_weights_dir).to(device, dtype)
    
    if device == "cuda":
        torch.cuda.empty_cache()

@torch.no_grad()
def run_triposg(
    image_input: Union[str, Image.Image],
    num_parts: int,
    seed: int,
    num_tokens: int = 1024,
    num_inference_steps: int = 50,
    guidance_scale: float = 7.0,
    max_num_expanded_coords: int = 1e9,
    use_flash_decoder: bool = False,
    rmbg: bool = False,
) -> Tuple[List[trimesh.Trimesh], Image.Image]:
    
    if rmbg:
        img_pil = prepare_image(image_input, bg_color=np.array([1.0, 1.0, 1.0]), rmbg_net=rmbg_net)
    else:
        if isinstance(image_input, str):
            img_pil = Image.open(image_input)
        else:
            img_pil = image_input
    
    start_time = time.time()
    outputs = pipe(
        image=[img_pil] * num_parts,
        attention_kwargs={"num_parts": num_parts},
        num_tokens=num_tokens,
        generator=torch.Generator(device=pipe.device).manual_seed(seed),
        num_inference_steps=num_inference_steps,
        guidance_scale=guidance_scale,
        max_num_expanded_coords=max_num_expanded_coords,
        use_flash_decoder=use_flash_decoder,
    ).meshes
    end_time = time.time()
    
    for i in range(len(outputs)):
        if outputs[i] is None:
            outputs[i] = trimesh.Trimesh(vertices=[[0, 0, 0]], faces=[[0, 0, 0]])
    
    return outputs, img_pil, end_time - start_time

def generate_parts(
    image,
    num_parts,
    seed,
    num_tokens,
    num_inference_steps,
    guidance_scale,
    use_flash_decoder,
    remove_background,
    render_output
):
    if image is None:
        return None, None, None, None, "Please upload an image first."
    
    try:
        # Load models if not already loaded
        load_models()
        
        # Set seed
        set_seed(seed)
        
        # Run inference
        outputs, processed_image, inference_time = run_triposg(
            image_input=image,
            num_parts=num_parts,
            seed=seed,
            num_tokens=num_tokens,
            num_inference_steps=num_inference_steps,
            guidance_scale=guidance_scale,
            use_flash_decoder=use_flash_decoder,
            rmbg=remove_background,
        )
        
        # Create temporary directory for outputs
        temp_dir = tempfile.mkdtemp()
        
        # Save individual parts
        part_files = []
        for i, mesh in enumerate(outputs):
            part_path = os.path.join(temp_dir, f"part_{i:02}.glb")
            mesh.export(part_path)
            part_files.append(part_path)
        
        # Create merged mesh
        merged_mesh = get_colored_mesh_composition(outputs)
        merged_path = os.path.join(temp_dir, "object.glb")
        merged_mesh.export(merged_path)
        
        # Render if requested
        rendered_image = None
        rendered_gif = None
        if render_output:
            num_views = 36
            radius = 4
            fps = 18
            
            rendered_images = render_views_around_mesh(
                merged_mesh,
                num_views=num_views,
                radius=radius,
            )
            
            rendered_normals = render_normal_views_around_mesh(
                merged_mesh,
                num_views=num_views,
                radius=radius,
            )
            
            rendered_grids = make_grid_for_images_or_videos(
                [
                    [processed_image] * num_views,
                    rendered_images,
                    rendered_normals,
                ], 
                nrow=3
            )
            
            # Save first rendered image
            rendered_image = rendered_images[0]
            
            # Save rendered GIF
            gif_path = os.path.join(temp_dir, "rendering.gif")
            export_renderings(rendered_images, gif_path, fps=fps)
            rendered_gif = gif_path
        
        # Clean up GPU memory
        if device == "cuda":
            torch.cuda.empty_cache()
        
        status_msg = f"Generated {len(outputs)} parts in {inference_time:.2f} seconds"
        
        return merged_path, rendered_image, rendered_gif, part_files, status_msg
        
    except Exception as e:
        if device == "cuda":
            torch.cuda.empty_cache()
        return None, None, None, None, f"Error: {str(e)}"

# Create Gradio interface
with gr.Blocks(title="PartCrafter", theme=gr.themes.Soft()) as demo:
    gr.Markdown("# PartCrafter")
    gr.Markdown("Generate 3D parts from a single image using PartCrafter")
    
    with gr.Row():
        with gr.Column(scale=1):
            # Input controls
            input_image = gr.Image(
                label="Input Image",
                type="pil",
                height=300
            )
            
            num_parts = gr.Slider(
                minimum=1,
                maximum=MAX_NUM_PARTS,
                value=3,
                step=1,
                label="Number of Parts"
            )
            
            with gr.Accordion("Advanced Settings", open=False):
                seed = gr.Slider(
                    minimum=0,
                    maximum=2147483647,
                    value=0,
                    step=1,
                    label="Seed"
                )
                
                num_tokens = gr.Slider(
                    minimum=256,
                    maximum=2048,
                    value=1024,
                    step=256,
                    label="Number of Tokens"
                )
                
                num_inference_steps = gr.Slider(
                    minimum=10,
                    maximum=100,
                    value=50,
                    step=5,
                    label="Inference Steps"
                )
                
                guidance_scale = gr.Slider(
                    minimum=1.0,
                    maximum=15.0,
                    value=7.0,
                    step=0.5,
                    label="Guidance Scale"
                )
                
                use_flash_decoder = gr.Checkbox(
                    label="Use Flash Decoder",
                    value=False
                )
                
                remove_background = gr.Checkbox(
                    label="Remove Background",
                    value=False
                )
                
                render_output = gr.Checkbox(
                    label="Render Output",
                    value=True
                )
            
            generate_btn = gr.Button("Generate Parts", variant="primary")
        
        with gr.Column(scale=2):
            # Output display
            status_text = gr.Textbox(
                label="Status",
                interactive=False
            )
            
            with gr.Row():
                with gr.Column():
                    merged_model = gr.File(
                        label="Merged Model (GLB)",
                        file_types=[".glb"]
                    )
                    
                    part_files = gr.File(
                        label="Individual Parts (GLB)",
                        file_count="multiple",
                        file_types=[".glb"]
                    )
                
                with gr.Column():
                    rendered_image = gr.Image(
                        label="Rendered View",
                        height=300
                    )
                    
                    rendered_gif = gr.File(
                        label="Rendered Animation (GIF)",
                        file_types=[".gif"]
                    )
    
    # Connect the generate button
    generate_btn.click(
        fn=generate_parts,
        inputs=[
            input_image,
            num_parts,
            seed,
            num_tokens,
            num_inference_steps,
            guidance_scale,
            use_flash_decoder,
            remove_background,
            render_output
        ],
        outputs=[
            merged_model,
            rendered_image,
            rendered_gif,
            part_files,
            status_text
        ]
    )
    
    # Add example
    gr.Examples(
        examples=[
            ["assets/images/np3_2f6ab901c5a84ed6bbdf85a67b22a2ee.png", 3, 0, 1024, 50, 7.0, False, False, True],
        ],
        inputs=[
            input_image,
            num_parts,
            seed,
            num_tokens,
            num_inference_steps,
            guidance_scale,
            use_flash_decoder,
            remove_background,
            render_output
        ]
    )

if __name__ == "__main__":
    demo.launch(
        server_name="0.0.0.0",
        server_port=7860,
        share=False