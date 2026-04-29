Download the North American Shapefiles from the link:
<https://www.cec.org/north-american-environmental-atlas/political-boundaries-2021/>
and copy the folder in this location

then make sure to have the right path on the R script:
E.g.

```r 
# ── 0. Load data ───────────────────────────────────────────────────────────────
NAR <- st_read("shape/politicalboundaries_shapefile/NA_PoliticalDivisions/data/boundaries_p_2021_v3.shp")
```

*note: in this repo only the .shp file was removed for the 100MB Github.com uploading cap*
