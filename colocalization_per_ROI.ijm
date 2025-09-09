// Colocalization per ROI (Pearson's r and Manders' M1/M2 with no thresholds)
// 1) Split/select two channels (indices you choose), Z-projection (max), 32-bit math-safe
// 2) For each ROI in ROI Manager (or whole image if none): compute r, M1, M2
// 3) Saves a tidy CSV with one row per ROI

//  User options 
ch1 = getNumber("First channel index (1 = first channel):", 1);
ch2 = getNumber("Second channel index (1 = first channel):", 2);
blurSigma = getNumber("Optional Gaussian blur sigma before measurement (0 = none):", 0);

// Choose output folder
outDir = getDirectory("Choose an output folder");

//  Prep image(s) 
origTitle = getTitle();
getDimensions(w, h, c, z, t);

// Duplicate to avoid altering original
run("Duplicate...", "title=work");

// If multi-channel, split channels; else the single image is used for both indices (guarded below)
if (c > 1) {
    selectWindow("work");
    run("Split Channels");
    ch1Title = "C" + ch1 + "-" + origTitle;
    ch2Title = "C" + ch2 + "-" + origTitle;
} else {
    ch1Title = "work";
    ch2Title = "work";
}

// Build Z-projections (max) for each chosen channel
selectWindow(ch1Title);
getDimensions(w1, h1, c1, z1, t1);
if (z1 > 1) run("Z Project...", "projection=[Max Intensity]"); else run("Duplicate...", "title=MAX_" + ch1Title);
rename("CH1");

selectWindow(ch2Title);
getDimensions(w2, h2, c2, z2, t2);
if (z2 > 1) run("Z Project...", "projection=[Max Intensity]"); else run("Duplicate...", "title=MAX_" + ch2Title);
rename("CH2");

// Ensure same size
selectWindow("CH1"); getDimensions(wA, hA, cA, zA, tA);
selectWindow("CH2"); getDimensions(wB, hB, cB, zB, tB);
if (wA != wB || hA != hB) {
    // Resize CH2 to match CH1
    selectWindow("CH2");
    run("Scale...", "x=" + (wA*1.0/wB) + " y=" + (hA*1.0/hB) + " width=" + wA + " height=" + hA + " interpolation=Bilinear create");
    close("CH2");
    rename("CH2");
}

// Optional blur (helps reduce shot noise before correlation)
if (blurSigma > 0) {
    selectWindow("CH1"); run("Gaussian Blur...", "sigma=" + blurSigma);
    selectWindow("CH2"); run("Gaussian Blur...", "sigma=" + blurSigma);
}

// Convert to 32-bit for math
selectWindow("CH1"); run("32-bit");
selectWindow("CH2"); run("32-bit");

// Prepare helper images
// Product CH1*CH2 and squares CH1^2, CH2^2 (used for Pearson's r)
selectWindow("CH1");
run("Duplicate...", "title=CH1_sq"); run("Square");
selectWindow("CH2");
run("Duplicate...", "title=CH2_sq"); run("Square");
run("Image Calculator...", "image1=CH1 operation=Multiply image2=CH2 create");
rename("CH1xCH2");

// A constant-ones image to count pixels (N) robustly via IntDen
newImage("ONES", "32-bit black", wA, hA, 1);
run("Add...", "value=1");

//  Collect ROIs 
needsWhole = false;
if (roiManager("count") == -1) roiManager("Reset"); // ensure manager exists
nROI = roiManager("count");
if (nROI == 0) {
    // Use whole image as a single ROI
    needsWhole = true;
    makeRectangle(0, 0, wA, hA);
    roiManager("Add");
}
nROI = roiManager("count");

//  Measurements setup 
run("Clear Results");
run("Set Measurements...", "area mean integrated redirect=None decimal=6 add");

//  Loop over ROIs 
for (i = 0; i < nROI; i++) {
    // Select base ROI
    roiManager("Select", i);
    // Name
    label = roiManager("Get Name", i);
    if (label == "") label = "ROI_" + IJ.pad(i+1, 3);

    // ----- Sums for Pearson -----
    // Sum X (CH1)
    selectWindow("CH1");
    run("Measure");
    sumX = getResult("IntDen", nResults-1);

    // Sum Y (CH2)
    selectWindow("CH2");
    run("Measure");
    sumY = getResult("IntDen", nResults-1);

    // Sum X^2
    selectWindow("CH1_sq");
    run("Measure");
    sumX2 = getResult("IntDen", nResults-1);

    // Sum Y^2
    selectWindow("CH2_sq");
    run("Measure");
    sumY2 = getResult("IntDen", nResults-1);

    // Sum XY
    selectWindow("CH1xCH2");
    run("Measure");
    sumXY = getResult("IntDen", nResults-1);

    // N pixels inside ROI via ONES image
    selectWindow("ONES");
    run("Measure");
    nPix = getResult("IntDen", nResults-1);

    // Compute Pearson's r
    // r = (N*sumXY - sumX*sumY) / sqrt( (N*sumX2 - sumX^2) * (N*sumY2 - sumY^2) )
    num = nPix*sumXY - sumX*sumY;
    denA = nPix*sumX2 - sumX*sumX;
    denB = nPix*sumY2 - sumY*sumY;
    if (denA <= 0 || denB <= 0) {
        r = NaN;
    } else {
        r = num / sqrt(denA*denB);
    }

    // ----- Manders' coefficients (no threshold) -----
    // M1 = sum(CH1 where CH2>0) / sum(CH1)
    // M2 = sum(CH2 where CH1>0) / sum(CH2)

    // Build selection for CH2>0 and intersect with base ROI
    selectWindow("CH2");
    // Determine max to set a tiny threshold
    getStatistics(a2, mean2, min2, max2, std2);
    if (max2 == 0) {
        // CH2 all zeros in ROI -> M1 = 0; M2 undefined (0/0) -> NaN
        sumCh1_coloc = 0;
    } else {
        setThreshold(1.0e-12, max2);
        run("Create Selection"); // selection where CH2>0
        // Save temporary selection
        roiManager("Add");
        idxTmp = roiManager("count") - 1;

        // Intersect with base ROI
        roiManager("Select", newArray(i, idxTmp));
        roiManager("AND");
        // Now measure CH1 within intersection
        selectWindow("CH1");
        run("Measure");
        sumCh1_coloc = getResult("IntDen", nResults-1);

        // Clean up temp
        roiManager("Select", idxTmp);
        roiManager("Delete");
    }

    // Build selection for CH1>0 and intersect with base ROI for M2
    selectWindow("CH1");
    getStatistics(a1, mean1, min1, max1, std1);
    if (max1 == 0) {
        sumCh2_coloc = 0;
    } else {
        setThreshold(1.0e-12, max1);
        run("Create Selection");
        roiManager("Add");
        idxTmp2 = roiManager("count") - 1;

        roiManager("Select", newArray(i, idxTmp2));
        roiManager("AND");

        selectWindow("CH2");
        run("Measure");
        sumCh2_coloc = getResult("IntDen", nResults-1);

        roiManager("Select", idxTmp2);
        roiManager("Delete");
    }

    // Compute Manders (guard against zero denominators)
    if (sumX <= 0) M1 = NaN; else M1 = sumCh1_coloc / sumX;
    if (sumY <= 0) M2 = NaN; else M2 = sumCh2_coloc / sumY;

    // ----- Write tidy row -----
    setResult("ID", i, i+1);
    setResult("ROI_Name", i, label);
    setResult("N_pixels", i, nPix);
    setResult("Sum_CH1", i, sumX);
    setResult("Sum_CH2", i, sumY);
    setResult("Pearson_r", i, r);
    setResult("Manders_M1", i, M1);
    setResult("Manders_M2", i, M2);
    updateResults();
}

//  Save 
baseName = File.nameWithoutExtension;
saveAs("Results", outDir + baseName + "_coloc.csv");

// Optional QA: save a composite PNG showing ROIs over a merge
// Create merge for visualization only
selectWindow("CH1"); run("8-bit"); rename("CH1_8");
selectWindow("CH2"); run("8-bit"); rename("CH2_8");
run("Merge Channels...", "c1=CH1_8 c2=CH2_8 create");
rename("merge");
roiManager("Show All with labels");
saveAs("PNG", outDir + baseName + "_coloc_overlay.png");

//  Tidy 
roiManager("Deselect");
if (needsWhole) { roiManager("Reset"); } // remove the whole-image ROI we added
run("Close All");
