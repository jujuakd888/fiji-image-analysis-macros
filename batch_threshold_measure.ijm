// Batch threshold + measurement for a folder of images 
// For each image: Z-proj (slice 1–2 if available), blur, chosen threshold (Moments/Yen/both),
// binary cleanup, save mask, per-object results (Mean via redirect), global mean inside mask, ROIs.

// Choose folders & options
inDir  = getDirectory("Choose input folder");
outDir = getDirectory("Choose output folder");
choice = getString("Threshold method (Moments, Yen, or Moments+Yen)", "Moments");

// Accept common image formats
list = getFileList(inDir);
setBatchMode(true);

for (i = 0; i < list.length; i++) {
    name = list[i];
    if (!(endsWith(name, ".tif") || endsWith(name, ".tiff") || endsWith(name, ".png") || endsWith(name, ".jpg") || endsWith(name, ".jpeg"))) {
        continue;
    }

    // Open image
    open(inDir + name);
    origTitle = getTitle();
    base = File.nameWithoutExtension(name);

    // Determine stack depth safely
    getDimensions(width, height, channels, slices, frames);

    // Z-Projection (max of slice 1–2 if stack; duplicate if single slice)
    if (slices >= 2) {
        stopSlice = 2;
        if (slices < 2) stopSlice = slices; // just in case
        run("Z Project...", "start=1 stop=" + stopSlice + " projection=[Max Intensity]");
    } else {
        run("Duplicate...", "title=ZProject");
    }
    rename("zp");

    // Blur for cleaner thresholding 
    run("Gaussian Blur...", "sigma=2");

    // Prep duplicates for flexible thresholding 
    run("Duplicate...", "title=temp1");
    run("Duplicate...", "title=temp2");

    // --- Create mask depending on choice
    if (choice == "Moments" || choice == "moments") {
        selectWindow("temp1"); setAutoThreshold("Moments dark");
        setOption("BlackBackground", false); run("Convert to Mask"); rename("mask");
    } else if (choice == "Yen" || choice == "yen") {
        selectWindow("temp1"); setAutoThreshold("Yen dark");
        setOption("BlackBackground", false); run("Convert to Mask"); rename("mask");
    } else { // Moments+Yen (intersection)
        selectWindow("temp1"); setAutoThreshold("Moments dark");
        setOption("BlackBackground", false); run("Convert to Mask"); rename("mask_Moments");
        selectWindow("temp2"); setAutoThreshold("Yen dark");
        setOption("BlackBackground", false); run("Convert to Mask"); rename("mask_Yen");
        run("Image Calculator...", "image1=mask_Moments operation=AND image2=mask_Yen create");
        rename("mask");
    }

    // Binary clean-up 
    selectWindow("mask");
    run("Options...", "iterations=1 count=1 black do=Open");
    run("Fill Holes");
    run("Make Binary");

    // Save mask 
    saveAs("Tiff", outDir + base + "_mask.tif");

    // Measurements: redirect to Z-projection for intensities
    run("Clear Results");
    run("Set Measurements...", "area mean min center perimeter shape integrated feret redirect=zp decimal=3 add");

    // Analyze Particles: per-object stats
    run("Analyze Particles...", "size=0-Infinity show=Nothing display exclude add clear");

    // Save per-object Results
    saveAs("Results", outDir + base + "_results.csv");

    // Save ROIs
    roiManager("Save", outDir + base + "_rois.zip");

    // Global average intensity inside the mask
    selectWindow("mask"); run("Create Selection");
    selectWindow("zp");  run("Measure"); // appends a global row to Results

    // Save combined Results (per-object + global)
    saveAs("Results", outDir + base + "_results_with_global.csv");

    // Tidy up for next file
    roiManager("Reset");
    run("Close All");
}

// Done
setBatchMode(false);
print("Batch complete.");
