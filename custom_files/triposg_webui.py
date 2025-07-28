import gradio as gr
import subprocess
import os
import glob
import trimesh
import shutil
import threading
import time
from queue import Queue

def run_triposg(image_input, output_format, progress=gr.Progress()):
    """Runs the TripoSR model with the given image input and converts to selected format."""
    start_time = time.time()
    
    try:
        # Create a temporary directory for output files
        output_dir = "temp_output"
        os.makedirs(output_dir, exist_ok=True)
        
        # Create public directory for serving files
        public_dir = "public"
        os.makedirs(public_dir, exist_ok=True)

        # Construct the command
        command = [
            "python",
            "-m",
            "scripts.inference_triposg",
            "--image-input",
            image_input,
            "--output-dir",
            output_dir,
        ]

        progress(0.1, desc="Working...")

        # Execute the command with real-time output display
        process = subprocess.Popen(
            command, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1
        )

        # Monitor process output and display terminal output in real-time
        output_lines = []
        while True:
            output = process.stdout.readline()
            if output == '' and process.poll() is not None:
                break
            if output:
                output_lines.append(output.strip())
                print(output.strip())  # Print to console for debugging
                
                # Display the actual terminal output in progress
                clean_output = output.strip()
                if clean_output:
                    progress(0.5, desc=clean_output)

        # Wait for process to complete
        return_code = process.poll()
        
        # Check for errors
        if return_code != 0:
            error_msg = '\n'.join(output_lines[-10:])  # Show last 10 lines
            return f"Error (code {return_code}): {error_msg}"

        progress(0.9, desc="Converting output format...")

        # Find the GLB file in the output directory
        glb_files = [f for f in os.listdir(output_dir) if f.endswith(".glb")]
        if not glb_files:
            return "No .glb file generated.", 0

        glb_file_path = os.path.join(output_dir, glb_files[0])
        base_name = os.path.splitext(glb_files[0])[0]
        output_file = os.path.join(public_dir, f"{base_name}.{output_format}")
        
        # Optimize file handling based on format
        if output_format == "glb":
            shutil.copy(glb_file_path, output_file)
        else:
            # Load mesh only when conversion is needed
            mesh = trimesh.load(glb_file_path)
            if output_format not in ["stl", "obj"]:
                return "Invalid output format selected.", 0
            mesh.export(output_file)
        
        # Calculate total processing time
        end_time = time.time()
        total_time = end_time - start_time
        minutes = int(total_time // 60)
        seconds = int(total_time % 60)
        
        time_str = f"{minutes}m {seconds}s" if minutes > 0 else f"{seconds}s"
        progress(1.0, desc=f"3D model generated in {time_str}!")
        
        # Return the path and processing time
        return output_file, total_time

    except Exception as e:
        return f"An error occurred: {str(e)}", 0

def run_triposg_with_time(image_input, output_format):
    """Wrapper function that tracks processing time."""
    if not image_input:
        return None, "Please upload an image first."
    
    # Run the actual processing
    result = run_triposg(image_input, output_format)
    
    if isinstance(result, tuple):
        output_file, processing_time = result
        if isinstance(output_file, str) and output_file.startswith("Error"):
            return None, output_file
        elif isinstance(output_file, str) and output_file.startswith("No .glb"):
            return None, output_file
        else:
            minutes = int(processing_time // 60)
            seconds = int(processing_time % 60)
            time_str = f"{minutes}m {seconds}s" if minutes > 0 else f"{seconds}s"
            return output_file, f"Generation completed in {time_str}"
    else:
        return None, "Unexpected error occurred."

# Get example images (cached)
example_dir = "assets/example_data/"
example_images = glob.glob(os.path.join(example_dir, "*.png")) if os.path.exists(example_dir) else []

# Create a custom Gradio interface with 3D model display
with gr.Blocks(title="TripoSR for ROCm") as iface:
    gr.Markdown("# TripoSR Inference for ROCm")
    gr.Markdown("Upload an image and generate a 3D model using TripoSR (Without textures). Choose your preferred output format.")
    gr.Markdown("⚠️ **Warning:** The model may not display in the preview window, but it is still available for download.")
    gr.Markdown("https://github.com/VAST-AI-Research/TripoSG<br>https://github.com/Mateusz-Dera/ROCm-AI-Installer")    
    
    with gr.Row():
        with gr.Column(scale=1):
            input_image = gr.Image(type="filepath", label="Input Image")
            output_format = gr.Radio(
                choices=["glb", "stl", "obj"], 
                value="glb", 
                label="Output Format",
                info="Select the format for your 3D model"
            )
            submit_btn = gr.Button("Generate 3D Model", variant="primary")
            

        with gr.Column(scale=1):
            model_output = gr.Model3D(label="3D Model Output")
            generation_time_text = gr.Markdown("")
    
    # Example images
    if example_images:
        gr.Examples(
            examples=example_images,
            inputs=input_image
        )
    
    # Set up the event handling for generating the model
    submit_btn.click(
        fn=run_triposg_with_time, 
        inputs=[input_image, output_format], 
        outputs=[model_output, generation_time_text],
        show_progress=True
    )

if __name__ == "__main__":
    iface.launch(share=False, server_name="0.0.0.0", allowed_paths=["public"])