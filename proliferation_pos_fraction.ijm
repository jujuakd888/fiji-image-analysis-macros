// Proliferation positive fraction (per nucleus)
// Steps:
// 1) Choose segmentation channel (nuclear stain) and marker channel (EdU/Ki67/etc.).
// 2) Segment nuclei (Moments/Yen/Moments+Yen) and get per-nucleus ROIs.
// 3) Measure per-nucleus mean intensity on the marker channel.
// 4) Classify positive vs negative using auto threshold (Yen/Otsu/Moments; Bright/Dark)
//    or a manual cutoff, then compute fraction positive.
// 5) Save CSV (per-cell + summary), ROIs, and a QA overlay image.

//  User options 
segChan   = getNumber("Segmentation (nuclear) channel index (1 = first channel):", 1);
markerChan= getNumber("Marker (EdU/Ki67/etc.) channel index (1 = first channel):", 2);
minSize   = getNumber("Minimum nucleus area (pixels^2):", 50);
segBlur   = getNumber("Optional Gaussian blur sigma for segmentation (0 = none):", 1);

// Segmentation threshold for nuclei
segChoice = getString("Nuclear threshold (Moments, Yen, or Moments+Yen):", "Yen");

// Marker classification method
classChoice = getString("Marker classification (Auto or Manual):", "Auto");
markerAuto  = "Yen"; // default auto method
if (classChoice == "Auto") {
    markerAuto = getString("Auto threshold method for marker (Yen, Otsu, Moments):", "Yen");
    markerPol  = getString("Marker polarity (Bright or Dark objects):", "Bright");
} else {
    manualCut  = getNumber("Manual cutoff for marker mean intensity:", 100.0);
    markerPol  = getString("Marker polarity relative to cutoff (Bright or Dark objects):", "Bright");
}

// Optional preprocessing on marker channel
doBG = getString("Subtract background on marker channel? (Yes/No)", "No");

// Choose output folder
outDir = getDirectory("Choose an output folder");

//  Prep image(s) 
origTitle = getTitle();
getDimensions(w, h, c, z, t);

// Work on a duplicate
run("Duplicate...", "title=work");

// Split channels if needed
if (c > 1) {
    selectWindow("work");
    run("Split Channels");
    segTitle    = "C" + segChan    + "-" + origTitle;
    markerTitle = "C" + markerChan + "-" + origTitle;
} else {
    segTitle    = "work";
    markerTitle = "work";
}

// Z-projection (max) for both channels (handles 3D; 2D just duplicates)
selectWindow(segTitle);
getDimensions(sw, sh, sc, sz, st);
if (sz > 1) run("Z Project...", "projection=[Max Intensity]"); else run("Duplicate...", "title=ZP_seg");
rename("ZP_seg");

selectWindow(markerTitle);
getDimensions(mw, mh, mc, mz, mt);
if (mz > 1) run("Z Project...", "projection=[Max Intensity]"); else run("Duplicate...", "title=ZP_marker");
rename("ZP_marker");

// Optional smoothing for segmentation
selectWindow("ZP_seg");
if (segBlur > 0) run("Gaussian Blur...", "sigma=" + segBlur);

// Optional background subtraction on marker channel
if (doBG == "Yes" || doBG == "yes") {
    selectWindow("ZP_marker");
    run("Subtract Background...", "rolling=50");
}

//  Nuclear mask 
selectWindow("ZP_seg");
run("Duplicate...", "title=tmp1");
run("Duplicate...", "title=tmp2");

if (segChoice == "Moments" || segChoice == "moments") {
    selectWindow("tmp1"); setAutoThreshold("Moments dark");
    setOption("BlackBackground", false); run("Convert to Mask"); rename("nuc_mask");
} else if (segChoice == "Yen" || segChoice == "yen") {
    selectWindow("tmp1"); setAutoThreshold("Yen dark");
    setOption("BlackBackground", false); run("Convert to Mask"); rename("nuc_mask");
} else { // Moments+Yen
    selectWindow("tmp1"); setAutoThreshold("Moments dark");
    setOption("BlackBackground", false); run("Convert to Mask"); rename("mask_M");
    selectWindow("tmp2"); setAutoThreshold("Yen dark");
    setOption("BlackBackground", false); run("Convert to Mask"); rename("mask_Y");
    run("Image Calculator...", "image1=mask_M operation=AND image2=mask_Y create");
    rename("nuc_mask");
}

// Binary cleanup
selectWindow("nuc_mask");
run("Options...", "iterations=1 count=1 black do=Open");
run("Fill Holes");
run("Make Binary");

//  ROIs per nucleus 
run("Set Measurements...", "area mean centroid perimeter shape redirect=None decimal=6 add");
run("Analyze Particles...", "size=" + minSize + "-Infinity show=Nothing display exclude add clear");
nNuc = roiManager("count");
if (nNuc <= 0) exit("No nuclei detected. Adjust segmentation parameters.");

//  Measure marker per nucleus 
selectWindow("ZP_marker");
run("Set Measurements...", "area mean integrated redirect=ZP_marker decimal=6 add");
run("Clear Results");

// Compute classification cutoff if Auto
autoCutoff = NaN;
if (classChoice == "Auto" || classChoice == "auto") {
    selectWindow("ZP_marker");
    // Compute auto threshold globally on marker image
    if (markerPol == "Dark" || markerPol == "dark") {
        setAutoThreshold(markerAuto + " dark");
    } else {
        setAutoThreshold(markerAuto);
    }
    // Read the threshold bounds
    getThreshold(lower, upper);
    // Heuristic: for Bright objects, use 'lower' as cutoff; for Dark, use 'upper'
    if (markerPol == "Dark" || markerPol == "dark") autoCutoff = upper; else autoCutoff = lower;
} else {
    autoCutoff = manualCut;
}

// Iterate ROIs: measure mean and classify
posCount = 0;
for (i = 0; i < nNuc; i++) {
    roiManager("Select", i);
    run("Measure");
    meanVal = getResult("Mean", i); // since table was empty, row index == i

    // Classification
    isPos = 0;
    if (markerPol == "Dark" || markerPol == "dark") {
        if (meanVal <= autoCutoff) isPos = 1;
    } else {
        if (meanVal >= autoCutoff) isPos = 1;
    }

    if (isPos == 1) posCount++;

    // Name ROIs for clarity
    baseName = "cell_" + IJ.pad(i+1, 4);
    if (isPos == 1) {
        roiManager("Rename", baseName + "_POS");
    } else {
        roiManager("Rename", baseName + "_NEG");
    }

    // Store tidy per-cell row
    setResult("ID", i, i+1);
    setResult("Marker_Mean", i, meanVal);
    setResult("Positive", i, isPos);
    updateResults();
}

// Summary
total = nNuc;
frac = (total > 0) ? (posCount*1.0/total) : NaN;

// Append a summary row at the end (with ID = 0)
setResult("ID", total, 0);
setResult("Marker_Mean", total, autoCutoff);
setResult("Positive", total, posCount + "/" + total + " (" + d2s(frac*100, 2) + "%)");
updateResults();

// Save tables & ROIs
base = File.nameWithoutExtension;
saveAs("Results", outDir + base + "_prolif_percell.csv");
roiManager("Save", outDir + base + "_prolif_rois.zip");

// QA overlay: draw POS in green, NEG in red on marker image
selectWindow("ZP_marker");
run("Duplicate...", "title=marker_overlay");
setOption("BlackBackground", false);
run("Colors...", "foreground=white background=black selection=yellow"); // initialize

// Draw outlines
setLineWidth(1);
for (i = 0; i < nNuc; i++) {
    name = roiManager("Get Name", i);
    roiManager("Select", i);
    if (endsWith(name, "_POS")) {
        setColor(0,255,0); // green
    } else {
        setColor(255,0,0); // red
    }
    run("Draw");
}
saveAs("PNG", outDir + base + "_prolif_overlay.png");

// Also write a brief summary file
saveSummary = File.open(outDir + base + "_prolif_summary.txt");
File.append("Image: " + origTitle, saveSummary);
File.append("Total nuclei: " + total, saveSummary);
File.append("Positive count: " + posCount, saveSummary);
File.append("Fraction positive: " + d2s(frac*100, 2) + " %", saveSummary);
File.append("Classification method: " + (classChoice == "Auto" ? (markerAuto + " (" + markerPol + ")") : ("Manual cutoff=" + autoCutoff + " (" + markerPol + ")")), saveSummary);
File.close(saveSummary);

// Tidy
roiManager("Deselect");
run("Close All");
