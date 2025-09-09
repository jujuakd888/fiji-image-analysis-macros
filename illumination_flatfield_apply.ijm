// Illumination correction (flat-field) builder + applier
// 1) Pick a folder of background images to build the flat-field (median projection + optional blur, normalized to mean=1)
// 2) Pick an input folder to correct and an output folder to save corrected images
// 3) Each input image is corrected as: corrected = max( (raw - dark_offset), 0 ) / flat_norm
//    where flat_norm has mean 1. Saves 16-bit by default.

// Choose folders
bgDir  = getDirectory("Choose BACKGROUND folder (used to build flat-field)");
inDir  = getDirectory("Choose INPUT folder (images to correct)");
outDir = getDirectory("Choose OUTPUT folder");

// Options
sigmaStr = getString("Gaussian blur sigma for flat-field smoothing (e.g., 10). Use 0 to skip blur:", "10");
sigma = parseFloat(sigmaStr);
darkStr = getString("Dark offset (constant to subtract from raw, e.g., 0–500; use 0 if none):", "0");
darkOffset = parseFloat(darkStr);
bitDepthChoice = getString("Output bit depth: 16 or 32", "16");

// Build flat-field from background folder
setBatchMode(true);
print("Building flat-field from: " + bgDir);

// Open sequence as a stack
run("Image Sequence...", "open=[" + bgDir + "] sort");
bgStackTitle = getTitle();

// Median projection to estimate flat-field
run("Z Project...", "projection=[Median]");
rename("flat_raw");

// Optional smoothing to remove sensor noise/puncta
if (sigma > 0) {
    run("Gaussian Blur...", "sigma=" + sigma);
}

// Convert to 32-bit for safe math
run("32-bit");

// Normalize flat-field to mean = 1.0
getStatistics(area, mean, min, max, std);
if (mean == 0) {
    exit("Error: Background images produced a zero-mean flat-field. Aborting.");
}
run("Divide...", "value=" + mean);

// Prevent zeros or negatives in flat-field (clip to small epsilon)
epsilon = 1.0e-6;
run("Subtract...", "value=0"); // ensure not NaN
// Create a duplicate and clip with Image Calculator to ensure min >= epsilon
run("Duplicate...", "title=flat_norm");
setMinAndMax(epsilon, 10); // just set display; actual values will be handled in calculation

// Save the normalized flat-field for record
saveAs("Tiff", outDir + "flatfield_normalized.tif");

// Clean up background stack
selectWindow(bgStackTitle); close();

// Correct each image in the input folder
list = getFileList(inDir);
for (i = 0; i < list.length; i++) {
    name = list[i];
    if (!(endsWith(name, ".tif") || endsWith(name, ".tiff") || endsWith(name, ".png") || endsWith(name, ".jpg") || endsWith(name, ".jpeg"))) {
        continue;
    }

    open(inDir + name);
    rawTitle = getTitle();
    base = File.nameWithoutExtension(name);

    // Convert raw to 32-bit for math
    run("32-bit");

    // If flat size doesn't match raw, resize a copy of flat to match
    selectWindow("flat_norm");
    getDimensions(fw, fh, fc, fs, ft);
    selectWindow(rawTitle);
    getDimensions(rw, rh, rc, rs, rt);

    if (fw != rw || fh != rh) {
        // Make a temporary resized flat
        selectWindow("flat_norm");
        run("Duplicate...", "title=flat_tmp");
        run("Scale...", "x=" + (rw*1.0/fw) + " y=" + (rh*1.0/fh) + " width=" + rw + " height=" + rh + " interpolation=Bilinear create");
        // Replace flat_tmp with scaled result for clarity
        close("flat_tmp");
        rename("flat_tmp");
    } else {
        // Use flat_norm directly
        selectWindow("flat_norm");
        run("Duplicate...", "title=flat_tmp");
    }

    // Ensure epsilon floor in flat_tmp (avoid divide by zero)
    // Approach: flat_tmp = max(flat_tmp, epsilon)
    // Create a constant image with epsilon and take Max
    newImage("eps_img", "32-bit black", rw, rh, 1);
    run("Add...", "value=" + epsilon);
    run("Image Calculator...", "image1=flat_tmp operation=Max image2=eps_img create");
    rename("flat_tmp2");
    close("flat_tmp"); close("eps_img");
    rename("flat_tmp"); // final temp flat

    // Subtract dark offset from raw, with floor at 0
    selectWindow(rawTitle);
    if (darkOffset != 0) {
        run("Subtract...", "value=" + darkOffset);
    }
    run("Max...", "value=0"); // clip negatives to 0

    // Divide raw by flat
    run("Image Calculator...", "image1=" + rawTitle + " operation=Divide image2=flat_tmp create");
    corrTitle = base + "_ff";
    rename(corrTitle);

    // Optionally convert to 16-bit for smaller files
    if (bitDepthChoice == "16" || bitDepthChoice == "16-bit" || bitDepthChoice == "16BIT") {
        // Scale to 16-bit dynamic range based on current min/max
        resetMinAndMax();
        run("16-bit");
    }

    // Save corrected image
    saveAs("Tiff", outDir + base + "_ff.tif");

    // Close per-file images
    close(rawTitle);
    close("flat_tmp");
    close(corrTitle);
}

// Leave flatfield image open? Save already; close it
if (isOpen("flat_norm")) close("flat_norm");

// Done
setBatchMode(false);
print("Flat-field built and applied. Output saved to: " + outDir);

//Notes
//The macro expects a folder of background frames (blank or evenly illuminated) to estimate the flat-field with a median projection—robust to dust/specks.
//The Gaussian blur (default 10 px) makes the field smooth; set to 0 to skip.
//Dark offset lets you subtract a constant camera offset if you know it; 0 is fine if you don’t.
//Output defaults to 16-bit; switch to 32 in the prompt if you prefer floating-point output.
//Saves the normalized flat-field as flatfield_normalized.tif in your output folder for orgin.