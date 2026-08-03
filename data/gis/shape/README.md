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

-------------
#### Term of use:

*This material is licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/), allowing non-exclusive rights to distribute, remix, adapt, and build upon the material in any medium or format, including for commercial purposes, so long as attribution is given to the creator.*

#### Citation:

*Commission for Environmental Cooperation (CEC). 2022. “North American Environmental Atlas - Political Boundaries”. Statistics Canada, United States Census Bureau, Instituto Nacional de Estadística y Geografía (INEGI). Ed. 3.0, Vector digital data [1:10,000,000]. Available at https://www.cec.org/north-american-environmental-atlas/political-boundaries-2021/*
