// --- Single image threshold + measurement ---
// Outputs: mask, per-object results, global mean, ROIs

// Save original title and ask where to save outputs
origTitle = getTitle();
outDir = getDirectory("Choose an output folder");

// --- Z-Projection (max of slice 1–2) ---
run("Z Project...", "start=1 stop=2 projection=[Max Intensity]");
rename("zp");

// --- Blur for cleaner thresholding ---
run("Gaussian Blur...", "sigma=2");

// --- Choose threshold method ---
choice = getString("Choose threshold method: Moments, Yen, or Moments+Yen", "Moments");

// --- Prep duplicates for flexible thresholding ---
run("Duplicate...", "title=temp1");
run("Duplicate...", "title=temp2");

// --- Create mask depending on choice ---
if (choice == "Moments" || choice == "moments") {
    selectWindow("temp1"); setAutoThreshold("Moments dark");
    setOption("BlackBackground", false); run("Convert to Mask"); rename("mask");
} else if (choice == "Yen" || choice == "yen") {
    selectWindow("temp1"); setAutoThreshold("Yen dark");
    setOption("BlackBackground", false); run("Convert to Mask"); rename("mask");
} else { // Moments+Yen
    selectWindow("temp1"); setAutoThreshold("Moments dark");
    setOption("BlackBackground", false); run("Convert to Mask"); rename("mask_Moments");
    selectWindow("temp2"); setAutoThreshold("Yen dark");
    setOption("BlackBackground", false); run("Convert to Mask"); rename("mask_Yen");
    run("Image Calculator...", "image1=mask_Moments operation=AND image2=mask_Yen create");
    rename("mask");
}

// --- Binary clean-up ---
selectWindow("mask");
run("Options...", "iterations=1 count=1 black do=Open");
run("Fill Holes");
run("Make Binary");

// --- Save mask ---
saveAs("Tiff", outDir + origTitle + "_mask.tif");

// --- Measurements: redirect to Z-projection for intensities ---
run("Set Measurements...", "area mean min center perimeter shape integrated feret redirect=zp decimal=3 add");

// --- Analyze Particles: per-object stats ---
run("Analyze Particles...", "size=0-Infinity show=Nothing display exclude add clear");

// Save Results table (per-object)
saveAs("Results", outDir + origTitle + "_results.csv");

// Save ROIs
roiManager("Save", outDir + origTitle + "_rois.zip");

// --- Global average intensity inside the mask ---
selectWindow("mask");
run("Create Selection"); // selection from mask
selectWindow("zp");
run("Measure"); // appends global mean to Results

// Save updated Results (per-object + global)
saveAs("Results", outDir + origTitle + "_results_with_global.csv");

// --- Tidy up ---
roiManager("Deselect"); roiManager("Reset");
run("Close All");
single_threshold_measure