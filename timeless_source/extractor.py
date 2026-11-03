import os
import re
from PIL import Image, ImageDraw, ImageFont

# Contenuto del file C trasmesso (sostituibile anche leggendo da file .c/.h)
c_code = """
#include "timeless.h"

unsigned char cspr00[]=
{
	 2,15, 0,0xc1,0xc1,
	 4,14, 1,0xc1,0xc2,0xc1,0xc2,
     // ... [Il resto del file C inserito qui]
"""

def parse_c_sprites(file_path_or_text):
    """
    Esegue il parsing degli array 'unsigned char csprXX[]' nel file C.
    """
    if os.path.exists(file_path_or_text):
        with open(file_path_or_text, "r") as f:
            text = f.read()
    else:
        text = file_path_or_text

    # Regex per trovare gli array csprXX
    pattern = re.compile(r'unsigned\s+char\s+(cspr[0-9a-fA-F]+)\[\]\s*=\s*\{([^\}]+)\};', re.MULTILINE)
    matches = pattern.findall(text)

    sprites = {}

    for name, data_str in matches:
        # Pulisci e converti i numeri da esadecimale/decimale
        tokens = re.findall(r'0x[0-9a-fA-F]+|\d+', data_str)
        values = [int(t, 16) if t.startswith('0x') else int(t) for t in tokens]

        spans = []
        i = 0
        while i < len(values):
            length = values[i]
            if length == 0:
                break
            x = values[i+1]
            y = values[i+2]
            pixels = values[i+3 : i+3+length]
            spans.append({'x': x, 'y': y, 'len': length, 'pixels': pixels})
            i += 3 + length

        sprites[name] = spans

    return sprites


def generate_correct_timeless_palette():
    """
    Ricostruisce la palette VGA RGB reale usata da Tran in Timeless 
    basandosi sulle rampe esadecimali presenti nei dati C.
    """
    palette = [(0, 0, 0, 0)] * 256  # 00 = Trasparente
    
    # 1. Rampa $C0 - $CF (Sfumature Rame / Arancione / Rosso Metallico)
    for i in range(16):
        idx = 0xC0 + i
        val = int((i / 15.0) * 255)
        # Sfumatura da scuro a brillante (Rame/Gold)
        palette[idx] = (val, int(val * 0.5), int(val * 0.2), 255)

    # 2. Rampa $D0 - $DF (Sfumature Grigio Acciaio / Chrome Metallico)
    for i in range(16):
        idx = 0xD0 + i
        val = int((i / 15.0) * 255)
        # Sfumatura scala di grigi metallica
        palette[idx] = (val, val, val, 255)

    # 3. Rampa $E0 - $EF (Sfumature Blu Profondo / Ciano / Elettrico)
    for i in range(16):
        idx = 0xE0 + i
        val = int((i / 15.0) * 255)
        # Sfumatura Blu / Ciano
        palette[idx] = (int(val * 0.2), int(val * 0.7), val, 255)

    # 4. Color fallback per indici generici (0x01 .. 0xBF)
    for i in range(1, 0xC0):
        # Assegna una scala di grigi lineare di sicurezza
        val = int((i / 191.0) * 255)
        palette[i] = (val, val, val, 255)

    return palette

def render_sprites_correct_colors(sprites, output_dir="correct_sprites", scale=4):
    os.makedirs(output_dir, exist_ok=True)
    palette = generate_correct_timeless_palette()
    images = []

    for name, spans in sprites.items():
        if not spans:
            continue

        max_x = max(span['x'] + span['len'] for span in spans)
        max_y = max(span['y'] for span in spans) + 1

        img = Image.new("RGBA", (max_x, max_y), (0, 0, 0, 0))
        pixels_img = img.load()

        for span in spans:
            y = span['y']
            for offset, p_val in enumerate(span['pixels']):
                x = span['x'] + offset
                # Applica il colore RGB mappato correttamente
                pixels_img[x, y] = palette[p_val]

        scaled_img = img.resize((max_x * scale, max_y * scale), Image.Resampling.NEAREST)

        # Salva PNG (Trasparente)
        scaled_img.save(os.path.join(output_dir, f"{name}.png"))

        # Salva JPG (Sfondo Nero)
        jpg_img = Image.new("RGB", scaled_img.size, (10, 10, 15))
        jpg_img.paste(scaled_img, (0, 0), scaled_img)
        jpg_img.save(os.path.join(output_dir, f"{name}.jpg"))

        images.append((name, jpg_img, max_x, max_y))

    # --- Generazione dell'Abaco Unico (Tutti in una pagina) ---
    if images:
        grid_cols = 5
        grid_rows = (len(images) + grid_cols - 1) // grid_cols
        cell_w, cell_h = 220, 220

        abaco = Image.new("RGB", (grid_cols * cell_w, grid_rows * cell_h), (10, 10, 15))
        draw = ImageDraw.Draw(abaco)

        for idx, (name, img_jpg, orig_w, orig_h) in enumerate(images):
            col = idx % grid_cols
            row = idx // grid_cols
            x_offset = col * cell_w
            y_offset = row * cell_h

            px = x_offset + (cell_w - img_jpg.width) // 2
            py = y_offset + (cell_h - img_jpg.height) // 2 + 10
            abaco.paste(img_jpg, (px, py))

            draw.rectangle([x_offset, y_offset, x_offset + cell_w - 1, y_offset + cell_h - 1], outline=(40, 40, 60))
            draw.text((x_offset + 8, y_offset + 8), f"{name} ({orig_w}x{orig_h})", fill=(0, 220, 255))

        abaco_path = os.path.join(output_dir, "tutti_gli_sprite_corretti.jpg")
        abaco.save(abaco_path, quality=95)
        print(f"-> Generato abaco con colori reali: {abaco_path}")

# Per testare direttamente:
# sprites = parse_c_sprites(c_code)
# render_sprites_correct_colors(sprites)

def generate_palette_gray():
    """
    Genera una palette a 256 colori pseudo-VGA/Grayscale 
    per mappare visivamente i valori dei pixel (es. 0xc1..0xff).
    """
    palette = []
    for i in range(256):
        # Mappa i valori con sfumature contrastate per evidenziare i dettagli 3D/Shading
        r = (i * 37) % 256
        g = (i * 59) % 256
        b = (i * 83) % 256
        palette.append((r, g, b, 255))
    palette[0] = (0, 0, 0, 0) # Trasparente
    return palette

def render_sprites(sprites, output_dir="extracted_sprites", scale=4):
    """
    Ricostruisce la matrice di pixel e salva i file PNG, JPG e l'Abaco complessivo.
    """
    os.makedirs(output_dir, exist_ok=True)
    images = []

    for name, spans in sprites.items():
        if not spans:
            continue

        # Calcola le dimensioni dello sprite (Width x Height)
        max_x = max(span['x'] + span['len'] for span in spans)
        max_y = max(span['y'] for span in spans) + 1

        # Crea immagine RGBA (Trasparente)
        img = Image.new("RGBA", (max_x, max_y), (0, 0, 0, 0))
        pixels_img = img.load()

        palette = generate_correct_timeless_palette()

        # Disegna gli span di pixel
        for span in spans:
            y = span['y']
            for offset, p_val in enumerate(span['pixels']):
                x = span['x'] + offset
                # Assegna il colore in base al byte
                r = (p_val * 7) % 256
                g = (p_val * 13) % 256
                b = (p_val * 29) % 256
                pixels_img[x, y] = (r, g, b, 255)

        # Ingrandisci l'immagine per una visione chiara (Pixel Art Scaling)
        scaled_img = img.resize((max_x * scale, max_y * scale), Image.Resampling.NEAREST)

        # Salva PNG singolo (Trasparente)
        scaled_img.save(os.path.join(output_dir, f"{name}.png"))

        # Salva JPG singolo (Sfondo Nero)
        jpg_img = Image.new("RGB", scaled_img.size, (20, 20, 20))
        jpg_img.paste(scaled_img, (0, 0), scaled_img)
        jpg_img.save(os.path.join(output_dir, f"{name}.jpg"))

        images.append((name, jpg_img, max_x, max_y))

    # --- Generazione Griglia / Abaco unico di tutti gli sprite ---
    if images:
        grid_cols = 6
        grid_rows = (len(images) + grid_cols - 1) // grid_cols
        cell_w, cell_h = 180, 180

        abaco = Image.new("RGB", (grid_cols * cell_w, grid_rows * cell_h), (15, 15, 20))
        draw = ImageDraw.Draw(abaco)

        for idx, (name, img_jpg, orig_w, orig_h) in enumerate(images):
            col = idx % grid_cols
            row = idx // grid_cols
            x_offset = col * cell_w
            y_offset = row * cell_h

            # Centra lo sprite nella cella
            px = x_offset + (cell_w - img_jpg.width) // 2
            py = y_offset + (cell_h - img_jpg.height) // 2 + 10
            abaco.paste(img_jpg, (px, py))

            # Disegna griglia e nome sprite
            draw.rectangle([x_offset, y_offset, x_offset + cell_w - 1, y_offset + cell_h - 1], outline=(50, 50, 70))
            draw.text((x_offset + 5, y_offset + 5), f"{name} ({orig_w}x{orig_h})", fill=(220, 220, 100))

        abaco_path = os.path.join(output_dir, "tutti_gli_sprite.jpg")
        abaco.save(abaco_path, quality=95)
        print(f"-> Generata pagina unica con tutti gli sprite: {abaco_path}")

if __name__ == "__main__":
    # Sostituisci 'timeless_sprites.c' con il percorso del tuo file se salvato su disco
    parsed_sprites = parse_c_sprites("timeless_sprites.c" if os.path.exists("timeless_sprites.c") else c_code)
    render_sprites(parsed_sprites)