// Nucleus–cytoplasm ratio (per cell)
// 1) Choose segmentation channel (nuclear stain) and measurement channel
// 2) Threshold nuclei (Moments / Yen / Moments+Yen), get per-nucleus ROIs
// 3) Build cytoplasmic ring by enlarging each nucleus and XOR (outer ⊕ inner)
// 4) Measure mean intensities in nucleus and ring on the measurement image
// 5) Export per-cell table with Nucleus_Mean, Cyto_Mean, and NC_Ratio

// User options 
ringStr   = getString("Cytoplasmic ring width (pixels):", "5");
ringWidth = parseFloat(ringStr);
minSize   = getNumber("Minimum nucleus size (pixels^2):", 50);
blurSigma = getNumber("Optional Gaussian blur sigma for segmentation (0 = none):", 1);
choice    = getString("Threshold method (Moments, Yen, or Moments+Yen):", "Yen");
segChan   = getNumber("Segmentation channel index (1 = first channel):", 1);
measChan  = getNumber("Measurement channel index (1 = first channel):", 1);

// Choose output folder
outDir = getDirectory("Choose an output folder");

//  Prep image(s)
origTitle = getTitle();
getDimensions(w, h, c, z, t);

// Work on a copy to avoid altering the original
run("Duplicate...", "title=work");

// If multi-channel, split channels
if (c > 1) {
    selectWindow("work");
    run("Split Channels");
    // Fiji names them C1-, C2-, ...
    segTitle  = "C" + segChan + "-" + origTitle;
    measTitle = "C" + measChan + "-" + origTitle;
} else {
    // Single-channel image
    segTitle  = "work";
    measTitle = "work";
}

// Create Z-projections (max) so we measure consistently on 2D
// Segmentation projection
selectWindow(segTitle);
getDimensions(sw, sh, sc, sz, st);
if (sz > 1) {
    run("Z Project...", "projection=[Max Intensity]");
    rename("seg_zp");
} else {
    run("Duplicate...", "title=seg_zp");
}

// Measurement projection
selectWindow(measTitle);
getDimensions(mw, mh, mc, mz, mt);
if (mz > 1) {
    run("Z Project...", "projection=[Max Intensity]");
    rename("meas_zp");
} else {
    run("Duplicate...", "title=meas_zp");
}

// Optional smoothing on the segmentation image
selectWindow("seg_zp");
if (blurSigma > 0) run("Gaussian Blur...", "sigma=" + blurSigma);

// Build nuclear mask 
run("Duplicate...", "title=temp1");
run("Duplicate...", "title=temp2");

if (choice == "Moments" || choice == "moments") {
    selectWindow("temp1"); setAutoThreshold("Moments dark");
    setOption("BlackBackground", false); run("Convert to Mask"); rename("nuc_mask");
} else if (choice == "Yen" || choice == "yen") {
    selectWindow("temp1"); setAutoThreshold("Yen dark");
    setOption("BlackBackground", false); run("Convert to Mask"); rename("nuc_mask");
} else { // Moments+Yen (intersection)
    selectWindow("temp1"); setAutoThreshold("Moments dark");
    setOption("BlackBackground", false); run("Convert to Mask"); rename("mask_M");
    selectWindow("temp2"); setAutoThreshold("Yen dark");
    setOption("BlackBackground", false); run("Convert to Mask"); rename("mask_Y");
    run("Image Calculator...", "image1=mask_M operation=AND image2=mask_Y create");
    rename("nuc_mask");
}

// Clean up mask: open → fill holes → binary
selectWindow("nuc_mask");
run("Options...", "iterations=1 count=1 black do=Open");
run("Fill Holes");
run("Make Binary");

//  Get per-nucleus ROIs
run("Set Measurements...", "area mean min centroid perimeter shape redirect=None decimal=3 add");
run("Analyze Particles...", "size=" + minSize + "-Infinity show=Nothing display exclude add clear");
nNuc = roiManager("count");

if (nNuc == 0) {
    exit("No nuclei detected. Try adjusting threshold method, blur, or minimum size.");
}

//Build cytoplasmic rings (per nucleus)
// Strategy: for each nucleus ROI -> duplicate ROI, enlarge by ringWidth, XOR with original to get ring
// ROIs will be named nuc_### and cyto_###
for (i = 0; i < nNuc; i++) {
    // Ensure we refer to correct ROI after additions
    roiManager("Select", i);
    roiManager("Rename", "nuc_" + IJ.pad(i+1, 4));

    // Duplicate current nucleus ROI as the "outer" candidate
    roiManager("Select", i);
    run("Enlarge...", "enlarge=" + ringWidth);
    roiManager("Add");
    idxOuter = roiManager("count") - 1;
    roiManager("Rename", "outer_" + IJ.pad(i+1, 4));

    // Select both (inner nucleus and outer) and XOR to make ring
    roiManager("Select", newArray(i, idxOuter));
    roiManager("XOR");
    roiManager("Add");
    idxRing = roiManager("count") - 1;
    roiManager("Rename", "cyto_" + IJ.pad(i+1, 4));

    // Optional: remove the temporary outer selection to keep ROI list tidy
    roiManager("Select", idxOuter);
    roiManager("Delete");
}

// Recount after adding rings
nTotal = roiManager("count");
nCells = nNuc; // one ring per nucleus

//Measure on measurement image 
selectWindow("meas_zp");
run("Set Measurements...", "area mean integrated redirect=meas_zp decimal=6 add");

// Clear Results to create a clean per-cell table
run("Clear Results");

// For each cell: measure nucleus mean, ring mean, compute N/C ratio; write one row per cell
row = 0;
for (i = 0; i < nCells; i++) {
    // Nucleus ROI is named nuc_####
    roiManager("Select", "nuc_" + IJ.pad(i+1, 4));
    run("Measure");
    nucMean = getResult("Mean", row);

    // Cyto ROI is named cyto_####
    roiManager("Select", "cyto_" + IJ.pad(i+1, 4));
    run("Measure");
    cytoMean = getResult("Mean", row+1);

    // Compute ratio (guard against divide-by-zero)
    if (cytoMean == 0) {
        ncr = NaN;
    } else {
        ncr = nucMean / cytoMean;
    }

    // Write a consolidated row (overwrite the first of the two rows we just added)
    setResult("ID",        row, i+1);
    setResult("Nucleus_Mean", row, nucMean);
    setResult("Cyto_Mean",    row, cytoMean);
    setResult("NC_Ratio",     row, ncr);

    // Remove the extra row (the second measurement row) to keep one row per cell
    // Note: Results table rows shift after deletion, so delete (row+1) now.
    updateResults();
    run("Select None");
    // Delete row+1 (second of the pair)
    call("ij.measure.ResultsTable.getResultsTable");
    run("Results...", ""); // ensure table focused
    // Workaround: recreate table without the extra row (simpler: clear and re-add—below)
    // Instead of deleting, we will rebuild a clean table after the loop.
    row = row + 2;
}

//Rebuild a clean per-cell table (ID, Nucleus_Mean, Cyto_Mean, NC_Ratio) 
nucleus_cytoplasm_ratio.// Extract existing values and write to a new table cleanly
// Approach: we already computed the values; recompute quickly to populate a fresh table.

run("Clear Results");
for (i = 0; i < nCells; i++) {
    roiManager("Select", "nuc_" + IJ.pad(i+1, 4));
    run("Measure"); // row i: nucleus
    nucMean = getResult("Mean", i);
}
run("Clear Results");
for (i = 0; i < nCells; i++) {
    // Recompute both means and append single tidy row
    roiManager("Select", "nuc_" + IJ.pad(i+1, 4));
    run("Measure");
    nucMean = getResult("Mean", 0);
    run("Clear Results");

    roiManager("Select", "cyto_" + IJ.pad(i+1, 4));
    run("Measure");
    cytoMean = getResult("Mean", 0);
    run("Clear Results");

    if (cytoMean == 0) ncr = NaN; else ncr = nucMean / cytoMean;

    // Write one row per cell
    setResult("ID", i, i+1);
    setResult("Nucleus_Mean", i, nucMean);
    setResult("Cyto_Mean", i, cytoMean);
    setResult("NC_Ratio", i, ncr);
}
updateResults();

// Save outputs
saveAs("Results", outDir + File.nameWithoutExtension + "_NC_results.csv");
roiManager("Save", outDir + File.nameWithoutExtension + "_NC_rois.zip");

// Optional QA overlay: draw ROIs on meas_zp and save a PNG
selectWindow("meas_zp");
run("Duplicate...", "title=meas_overlay");
roiManager("Show All with labels");
saveAs("PNG", outDir + File.nameWithoutExtension + "_NC_overlay.png");

// Tidy up
roiManager("Deselect");
roiManager("Reset");
run("Close All");
