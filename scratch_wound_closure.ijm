// Scratch/Wound Closure Analysis
// - Works on a time-lapse image or hyperstack (phase-contrast or fluorescence)
// - Measures wound area inside a user-defined ROI at each timepoint
// - Outputs % closure relative to frame 1, plus saves QA masks per timepoint
// Tips:
//   1) If you have a folder of single images per timepoint, first import as a stack:
//      File ▸ Import ▸ Image Sequence… (sorted by name) → then run this macro.
//   2) If multi-channel, you can choose which channel to analyze.
//   3) If cells are darker than background (common in phase-contrast), leave the default.

macro "Scratch Wound Closure" {
    //scratch_wound_closure Parameters 
    outDir = getDirectory("Choose an output folder");
    method = getString("Threshold method (e.g. Otsu, Yen, Moments, Triangle)", "Otsu");
    blurSigma = getNumber("Gaussian blur sigma (px)", 2.0);
    cellsDarker = getBoolean("Are CELLS darker than background?", true);
    frameIntervalMin = getNumber("Frame interval (minutes)", 5.0); // used for time axis
    chanToUse =  getNumber("Channel to analyze (1 for single-channel)", 1);

    //  Setup image 
    origTitle = getTitle();
    getDimensions(w, h, ch, z, t);
    // If hyperstack, split channels, keep the requested one.
    if (ch > 1) {
        run("Split Channels");
        // Split names look like "C1-<origTitle>", "C2-<origTitle>", ...
        selectWindow("C"+chanToUse+"-"+origTitle);
        // Close other channels
        for (c=1; c<=ch; c++) {
            if (c!=chanToUse) {
                titleToClose = "C"+c+"-"+origTitle;
                if (isOpen(titleToClose)) selectWindow(titleToClose), close();
            }
        }
    }

    // Ensure we work on a simple stack (no hyperstack axes)
    getDimensions(w, h, ch2, z2, t2);
    if (t2>1 || ch2>1) {
        // Flatten to simple stack with order XYZCT -> a single Z stack
        run("Hyperstack to Stack", "order=xyczt channels");
    }

    // Re-fetch dimensions after conversion
    getDimensions(w, h, chF, slices, framesDummy);
    if (slices < 1) slices = 1;

    //  Ask user to draw ROI 
    // The ROI should cover the entire scratch region & adjacent cells you want analyzed.
    waitForUser("Draw a rectangular ROI that covers the WOUND and adjacent cells (analysis region), then click OK.");
    roiManager("Reset");
    roiManager("Add"); // store as index 0

    //  Prepare Results table 
    if (isOpen("Results")) {
        selectWindow("Results");
        run("Clear Results");
    }
    setResult("image", 0, stripExtension(getTitle())); // placeholder to create headers
    updateResults();
    // We'll write rows manually below.

    //  Loop over timepoints (stack slices) 
    baseName = stripExtension(getTitle());
    baseWound = -1;

    // Create a per-frame subfolder for QA images
    qaDir = outDir + File.separator + baseName + "_QA" + File.separator;
    File.makeDirectory(qaDir);

    row = 0;
    for (i = 1; i <= slices; i++) {
        setSlice(i);
        roiManager("Select", 0);

        // Work on a cropped copy of the ROI area to simplify area accounting
        run("Duplicate...", "title=work");
        selectWindow("work");

        // Preprocess
        run("Gaussian Blur...", "sigma=" + blurSigma);

        // Optionally invert logic by telling the threshold whether objects are darker or brighter
        if (cellsDarker) setAutoThreshold(method + " dark");
        else             setAutoThreshold(method);

        setOption("BlackBackground", false);
        run("Convert to Mask");

        // Clean up binary (remove speckles, smooth edges)
        run("Options...", "iterations=1 count=1 black do=Open");
        run("Fill Holes");
        run("Make Binary");

        // Compute cell area (white pixels) from binary mean on 0..255
        getStatistics(roiAreaPx, meanVal, minVal, maxVal, stdVal); // roiAreaPx here means total pixels in ROI crop
        cellAreaPx = roiAreaPx * (meanVal/255.0);
        woundAreaPx = roiAreaPx - cellAreaPx;

        // Establish baseline wound area at first timepoint
        if (i == 1) baseWound = woundAreaPx;

        // % closure relative to first frame
        closurePct = 100.0 * (1.0 - woundAreaPx / baseWound);

        // Time axis
        timeMin = (i - 1) * frameIntervalMin;

        // Save QA mask image
        tStr = IJ.pad(i, 4);
        saveAs("PNG", qaDir + baseName + "_t" + tStr + "_mask.png");

        // Record to Results
        setResult("image",       row, baseName);
        setResult("t_index",     row, i);
        setResult("time_min",    row, d2s(timeMin, 3));
        setResult("roi_area_px", row, d2s(roiAreaPx, 3));
        setResult("cell_area_px",row, d2s(cellAreaPx, 3));
        setResult("wound_area_px",row,d2s(woundAreaPx, 3));
        setResult("closure_pct", row, d2s(closurePct, 3));
        row++;

        close("work");
        selectWindow(baseName); // return focus to main stack
    }

    //  Save outputs 
    resultsPath = outDir + File.separator + baseName + "_scratch_closure.csv";
    saveAs("Results", resultsPath);

    // Save the ROI that was used
    roiPath = outDir + File.separator + baseName + "_analysis_roi.zip";
    roiManager("Select", 0);
    roiManager("Save", roiPath);

    // Optional: save a quick plot of closure vs. time
    // (uncomment the next two lines if you want the plot saved as well)
    // run("Distribution...", "parameter=closure_pct automatic"); // will plot last column by default
    // saveAs("PNG", outDir + File.separator + baseName + "_closure_plot.png");

    // Done
    showMessage("Scratch/Wound Closure",
        "Done!\n\nSaved:\n- " + resultsPath +
        "\n- " + roiPath +
        "\n- QA masks in: " + qaDir);
}

//  Helpers 
function stripExtension(name) {
    dot = lastIndexOf(name, ".");
    if (dot==-1) return name;
    return substring(name, 0, dot);
}
