# Fiji Image Analysis Macros

An open-source toolkit of **Fiji (ImageJ) macros** for quantitative image analysis, developed to support reproducible research in molecular farming, stem cell biology, and cancer studies.

This repository contains a collection of custom Fiji macros designed for automated segmentation, intensity measurements, and morphological quantification. The tools support workflows commonly required in:

- **Molecular farming** – quantifying expression and localization patterns in engineered plant tissues  
- **Stem cell biology** – assessing proliferation, differentiation, and morphological changes  
- **Cancer research** – analyzing migration, apoptosis, 3D spheroid growth, and related assays  

By streamlining image processing and measurement tasks, these macros help researchers generate consistent, high-quality data across diverse imaging experiments.  
All code is open-source and may be adapted to project-specific needs.

---

## Macro Index

Each macro is **ready to use** in Fiji (ImageJ). Typical outputs include CSV tables, ROI sets, binary masks, and QA overlays.

| Macro | Description |
|---|---|
| `single_threshold_measure.ijm` | Thresholds one image (Moments/Yen/AND), saves mask, per-object stats, and global average intensity. |
| `batch_threshold_measure.ijm` | Processes an entire folder; same as single-image but runs across many files. |
| `illumination_flatfield_apply.ijm` | Builds a normalized flat-field from background frames and applies it to all images. |
| `nucleus_cytoplasm_ratio.ijm` | Computes per-cell nucleus-to-cytoplasm intensity ratios. |
| `colocalization_per_ROI.ijm` | Calculates Pearson’s *r* and Manders’ coefficients per ROI between two channels. |
| `proliferation_pos_fraction.ijm` | Quantifies the fraction of marker-positive cells (e.g., EdU, Ki67, H3P). |
| `apoptosis_marker_quant.ijm` | Measures apoptosis markers per cell and classifies cells as positive/negative. |
| `scratch_wound_closure.ijm` | Tracks wound area over time and computes % closure in scratch assays. |

---

## How to Run (GUI)
1. Open an image (or a stack) in Fiji.  
2. Go to `Plugins → Macros → New…` → paste code → `Run`.  
3. When prompted, choose thresholds/parameters and an **output folder**.  

## How to Run (Headless / Batch)
```bash
# macOS/Linux
/path/to/Fiji.app/Contents/MacOS/ImageJ-macosx --headless --console -macro macros/batch_threshold_measure.ijm

# Windows
"C:\path\to\Fiji.app\ImageJ-win64.exe" --headless --console -macro macros/batch_threshold_measure.ijm
