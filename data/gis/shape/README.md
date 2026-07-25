# North American political boundaries

Every part of the shapefile is in this repository **except the `.shp` geometry
itself**, which exceeds GitHub's 100 MB upload cap.

To restore it, download the *Political Boundaries 2021* dataset from

<https://www.cec.org/north-american-environmental-atlas/political-boundaries-2021/>

and drop `boundaries_p_2021_v3.shp` next to the other parts, so that this path exists:

```
data/gis/shape/politicalboundaries_shapefile/NA_PoliticalDivisions/data/boundaries_p_2021_v3.shp
```

`src/plotting/plot_maps_NA.R` resolves that path automatically and stops with a
clear message if the file is missing — no path editing required.
