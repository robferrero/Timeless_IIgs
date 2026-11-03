import os
import re
from PIL import Image, ImageDraw, ImageFont

def parse_c_sprites(file_path):
    """
    Legge il file C e analizza gli array 'unsigned char csprXX[]'.
    """
    if not os.path.exists(file_path):
        print(f"Errore: Il file {file_path} non esiste!")
        return {}

    with open(file_path, "r", encoding="utf-8") as f:
        text = f.read()

    # Regex per estrarre il nome dell'array e il suo contenuto
    pattern = re.compile(r'unsigned\s+char\s+(cspr[0-9a-fA-F]+)\[\]\s*=\s*\{([^\}]+)\};', re.MULTILINE)
    matches = pattern.findall(text)

    sprites = {}

    for name, data_str in matches:
        # Pulisci e converti i valori esadecimali e decimali
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


def get_real_timeless_vga_palette():
    """
    Restituisce la vera palette VGA RGB (256 colori) usata dal motore di Timeless.
    Mappa correttamente le rampe 0xC0..0xFF usate dagli sprite.
    """
    palette = [(0, 0, 0, 0)] * 256  # Index 0 = Trasparente / Sfondo

    # Rampa $C0 - $CF: Rame / Bronzo / Oro Metallico (Sfumature Calde)
    copper_ramp = [
        (0,0,0), (32,8,0), (64,16,0), (96,32,0),
        (128,48,0), (160,64,0), (192,88,0), (224,112,0),
        (255,140,0), (255,168,32), (255,192,64), (255,216,96),
        (255,232,128), (255,244,160), (255,255,192), (255,255,255)
    ]
    for i, rgb in enumerate(copper_ramp):
        palette[0xC0 + i] = (rgb[0], rgb[1], rgb[2], 255)

    # Rampa $D0 - $DF: Cromo / Acciaio Silver (Grigi metallici con toni freddi)
    steel_ramp = [
        (0,0,0), (12,14,20), (24,28,36), (40,44,56),
        (56,60,76), (76,80,100), (96,100,120), (116,124,144),
        (140,148,168), (164,172,192), (188,196,212), (208,216,228),
        (224,232,240), (240,244,248), (248,252,255), (255,255,255)
    ]
    for i, rgb in enumerate(steel_ramp):
        palette[0xD0 + i] = (rgb[0], rgb[1], rgb[2], 255)

    # Rampa $E0 - $EF: Bagliore Blu / Viola Elettrico
    glow_ramp = [
        (0,0,0), (8,0,32), (16,0,64), (32,0,96),
        (48,16,128), (64,32,160), (88,48,192), (112,64,224),
        (136,88,255), (160,112,255), (184,136,255), (208,160,255),
        (224,184,255), (240,208,255), (248,232,255), (255,255,255)
    ]
    for i, rgb in enumerate(glow_ramp):
        palette[0xE0 + i] = (rgb[0], rgb[1], rgb[2], 255)

    # Sfumatura di sicurezza per indici generici (0x01 .. 0xBF)
    for i in range(1, 0xC0):
        val = int((i / 191.0) * 220)
        palette[i] = (val, val, val, 255)

    return palette


def render_sprites_exact_vga(sprites, output_dir="exact_vga_sprites", scale=4):
    """
    Ricostruisce gli sprite e li salva in PNG, JPG e nell'abaco complessivo.
    """
    os.makedirs(output_dir, exist_ok=True)
    palette = get_real_timeless_vga_palette()
    images = []

    print(f"Elaborazione di {len(sprites)} sprite...")

    for name, spans in sprites.items():
        if not spans:
            continue

        # Dimensione dinamica dell'immagine per questo sprite
        max_x = max(span['x'] + span['len'] for span in spans)
        max_y = max(span['y'] for span in spans) + 1

        img = Image.new("RGBA", (max_x, max_y), (0, 0, 0, 0))
        pixels_img = img.load()

        # Disegna ogni span di pixel
        for span in spans:
            y = span['y']
            for offset, p_val in enumerate(span['pixels']):
                x = span['x'] + offset
                pixels_img[x, y] = palette[p_val]

        # Ingrandisci con Pixel-Art Resampling (senza sfocatura)
        scaled_img = img.resize((max_x * scale, max_y * scale), Image.Resampling.NEAREST)

        # Salva PNG (Trasparente)
        png_path = os.path.join(output_dir, f"{name}.png")
        scaled_img.save(png_path)

        # Salva JPG (Sfondo Scuro Elegante)
        jpg_img = Image.new("RGB", scaled_img.size, (10, 10, 15))
        jpg_img.paste(scaled_img, (0, 0), scaled_img)
        jpg_path = os.path.join(output_dir, f"{name}.jpg")
        jpg_img.save(jpg_path)

        images.append((name, jpg_img, max_x, max_y))

    # --- Generazione della Pagina Unica (Abaco) ---
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

            # Centra lo sprite nella cella
            px = x_offset + (cell_w - img_jpg.width) // 2
            py = y_offset + (cell_h - img_jpg.height) // 2 + 10
            abaco.paste(img_jpg, (px, py))

            # Griglia e Etichetta
            draw.rectangle([x_offset, y_offset, x_offset + cell_w - 1, y_offset + cell_h - 1], outline=(40, 40, 60))
            draw.text((x_offset + 8, y_offset + 8), f"{name} ({orig_w}x{orig_h}px)", fill=(255, 200, 50))

        abaco_path = os.path.join(output_dir, "tutti_gli_sprite_vga_reali.jpg")
        abaco.save(abaco_path, quality=95)
        print(f"\n-> COMPLETATO! Estratti {len(images)} sprite.")
        print(f"-> Trovi tutti i file singoli e l'Abaco complessivo in: {os.path.abspath(output_dir)}")


if __name__ == "__main__":
    # Nome del file sorgente C contenente gli sprite
    c_filename = "sprites.c"

    # Se vuoi specificare un altro percorso o nome file:
    if not os.path.exists(c_filename):
        # Cerca un file .c qualsiasi nella cartella corrente se sprites.c non esiste
        c_files = [f for f in os.listdir(".") if f.endswith(".c")]
        if c_files:
            c_filename = c_files[0]

    parsed_sprites = parse_c_sprites(c_filename)
    if parsed_sprites:
        render_sprites_exact_vga(parsed_sprites)
    else:
        print("Impossibile estrarre gli sprite. Verifica che il file .c sia presente nella cartella.")