import gradio as gr
import os
import sys
import torch
import tempfile
from pathlib import Path

# Add the project root to Python path
sys.path.insert(0, os.path.dirname(__file__))

from heartlib import HeartMuLaGenPipeline

# Global variables
pipe = None
device = "cuda" if torch.cuda.is_available() else "cpu"

def load_model(model_path: str = "./ckpt", version: str = "3B", lazy_load: bool = True):
    global pipe

    if pipe is not None:
        return "Model already loaded"

    try:
        pipe = HeartMuLaGenPipeline.from_pretrained(
            model_path,
            device={
                "mula": torch.device(device),
                "codec": torch.device(device),
            },
            dtype={
                "mula": torch.bfloat16,
                "codec": torch.float32,
            },
            version=version,
            lazy_load=lazy_load,
        )
        return f"Model loaded successfully on {device}"
    except Exception as e:
        return f"Error loading model: {str(e)}"

def generate_music(
    lyrics: str,
    tags: str,
    max_audio_length_ms: int = 240000,
    topk: int = 50,
    temperature: float = 1.0,
    cfg_scale: float = 1.0,
):
    global pipe

    if pipe is None:
        return None, "Model not loaded. Please load the model first."

    try:
        # Create temporary files for lyrics and tags
        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as lyrics_file:
            lyrics_file.write(lyrics)
            lyrics_path = lyrics_file.name

        with tempfile.NamedTemporaryFile(mode='w', suffix='.txt', delete=False) as tags_file:
            tags_file.write(tags)
            tags_path = tags_file.name

        # Create temporary output file (use .wav as mp3 requires additional codecs)
        output_path = tempfile.mktemp(suffix='.wav')

        with torch.no_grad():
            pipe(
                {
                    "lyrics": lyrics_path,
                    "tags": tags_path,
                },
                max_audio_length_ms=max_audio_length_ms,
                save_path=output_path,
                topk=topk,
                temperature=temperature,
                cfg_scale=cfg_scale,
            )

        # Clean up temp files
        os.unlink(lyrics_path)
        os.unlink(tags_path)

        return output_path, "Music generated successfully!"

    except Exception as e:
        return None, f"Error generating music: {str(e)}"

# Default lyrics example
DEFAULT_LYRICS = """[Intro]

[Verse]
The sun creeps in across the floor
I hear the traffic outside the door
The coffee pot begins to hiss
It is another morning just like this

[Prechorus]
The world keeps spinning round and round
Feet are planted on the ground
I find my rhythm in the sound

[Chorus]
Every day the light returns
Every day the fire burns
We keep on walking down this street
Moving to the same steady beat
It is the ordinary magic that we meet

[Outro]
Just another day
Every single day
"""

DEFAULT_TAGS = "piano,happy,pop,synthesizer,romantic"

# Create Gradio interface
with gr.Blocks(title="HeartMuLa Music Generation") as demo:
    gr.Markdown("# HeartMuLa Music Generation")
    gr.Markdown("Generate music from lyrics and tags using HeartMuLa model")

    with gr.Row():
        with gr.Column():
            model_path = gr.Textbox(
                label="Model Path",
                value="./ckpt",
                info="Path to the pretrained model checkpoint"
            )
            version = gr.Dropdown(
                label="Model Version",
                choices=["3B", "7B"],
                value="3B",
                info="HeartMuLa model version"
            )
            lazy_load = gr.Checkbox(
                label="Lazy Load",
                value=True,
                info="Load modules on demand to save GPU memory"
            )
            load_btn = gr.Button("Load Model", variant="primary")
            load_status = gr.Textbox(label="Status", interactive=False)

    gr.Markdown("---")

    with gr.Row():
        with gr.Column():
            lyrics = gr.Textbox(
                label="Lyrics",
                value=DEFAULT_LYRICS,
                lines=20,
                info="Enter lyrics with structure tags like [Verse], [Chorus], etc."
            )
            tags = gr.Textbox(
                label="Tags",
                value=DEFAULT_TAGS,
                info="Comma-separated tags (e.g., piano,happy,pop)"
            )

        with gr.Column():
            max_length = gr.Slider(
                label="Max Audio Length (ms)",
                minimum=30000,
                maximum=480000,
                value=240000,
                step=10000,
                info="Maximum length of generated audio"
            )
            topk = gr.Slider(
                label="Top-K",
                minimum=1,
                maximum=100,
                value=50,
                step=1,
                info="Top-k sampling parameter"
            )
            temperature = gr.Slider(
                label="Temperature",
                minimum=0.1,
                maximum=2.0,
                value=1.0,
                step=0.1,
                info="Sampling temperature"
            )
            cfg_scale = gr.Slider(
                label="CFG Scale",
                minimum=1.0,
                maximum=5.0,
                value=1.0,
                step=0.1,
                info="Classifier-free guidance scale (values > 1.0 may cause issues on AMD GPUs)"
            )

    generate_btn = gr.Button("Generate Music", variant="primary")

    with gr.Row():
        audio_output = gr.Audio(label="Generated Music", type="filepath")
        gen_status = gr.Textbox(label="Generation Status", interactive=False)

    # Event handlers
    load_btn.click(
        fn=load_model,
        inputs=[model_path, version, lazy_load],
        outputs=load_status
    )

    generate_btn.click(
        fn=generate_music,
        inputs=[lyrics, tags, max_length, topk, temperature, cfg_scale],
        outputs=[audio_output, gen_status]
    )

if __name__ == "__main__":
    import argparse
    import socket
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", action="store_true", help="Listen on 0.0.0.0")
    parser.add_argument("--port", type=int, default=7860, help="Port to listen on")
    args = parser.parse_args()

    def find_free_port(start_port, max_attempts=100):
        for port in range(start_port, start_port + max_attempts):
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.bind(("", port))
                    return port
            except OSError:
                continue
        return None

    server_name = "0.0.0.0" if args.listen else "127.0.0.1"
    port = find_free_port(args.port)
    if port != args.port:
        print(f"Port {args.port} is busy, using port {port}")
    demo.launch(server_name=server_name, server_port=port)
