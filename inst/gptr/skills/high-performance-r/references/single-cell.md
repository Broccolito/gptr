# Single-cell at scale

The Seurat or SingleCellExperiment object in the session may have taken minutes to load.
Never reload it, never `as.matrix()` its counts, and never `print()` it whole. Check with
`dim(obj)`, `Assays(obj)`, `Layers(obj)`, `object.size(obj)` and `gptr$describe(obj)`.

## Seurat v5

- Assays are v5 `Assay5` objects with **layers** (`counts`, `data`, `scale.data`, or one
  layer per sample after splitting). Access: `LayerData(obj, assay = "RNA", layer = "counts")`
  or `obj[["RNA"]]$counts`.
- Split by sample for integration, then join:
  `obj[["RNA"]] = split(obj[["RNA"]], f = obj$sample)` ... `IntegrateLayers(obj, method = CCAIntegration, ...)` ... `obj = JoinLayers(obj)`.
- Very large data: `SketchData(obj, ncells = 50000, method = "LeverageScore", sketched.assay = "sketch")`,
  analyse the sketch, then `ProjectData()` back to all cells.
- On-disk counts with **BPCells** (not on CRAN; check that `<r_env>` says it is loadable):
  ```r
  # BPCells::write_matrix_dir(mat = counts, dir = "counts_bp")   # once, dgCMatrix -> bit-packed on disk
  # counts_disk = BPCells::open_matrix_dir(dir = "counts_bp")
  # obj = SeuratObject::CreateSeuratObject(counts = counts_disk)
  # obj[["RNA"]]$counts = as(obj[["RNA"]]$counts, "dgCMatrix")   # back to memory if small enough
  ```
- Seurat parallelises some steps with `future`; with large objects raise
  `options(future.globals.maxSize = ...)` only when RAM allows (every worker receives a copy).

```r
# small, runnable illustration of v5 layers
library(Seurat)
m = Matrix::rsparsematrix(2000, 600, density = 0.05)
m@x = abs(round(m@x * 10)) + 1
rownames(m) = paste0("g", 1:2000)
colnames(m) = paste0("c", 1:600)
obj = CreateSeuratObject(counts = m)
obj$sample = rep(c("a", "b"), each = 300)
obj[["RNA"]] = split(obj[["RNA"]], f = obj$sample)
print(Layers(obj))                        # counts.a, counts.b
obj = JoinLayers(obj)
print(Layers(obj))                        # counts
obj = NormalizeData(obj, verbose = FALSE)
```

## SingleCellExperiment + on-disk arrays (Bioconductor)

```r
library(SingleCellExperiment)
m = Matrix::rsparsematrix(1000, 300, density = 0.05)
m@x = abs(m@x)
sce = SingleCellExperiment(assays = list(counts = m))
h5 = tempfile(fileext = ".h5")
disk = HDF5Array::writeHDF5Array(counts(sce), filepath = h5, name = "counts", as.sparse = TRUE)
DelayedArray::setAutoBlockSize(1e8)       # block size in bytes for block processing
cs = DelayedArray::colSums(disk)          # computed block by block from disk
d = tempfile()
HDF5Array::saveHDF5SummarizedExperiment(sce, d)      # whole object, assays on disk
sce2 = HDF5Array::loadHDF5SummarizedExperiment(d)    # counts(sce2) is an HDF5Matrix
```

## Plotting cells

`DimPlot()`/`FeaturePlot()` with >1e5 cells: add `raster = TRUE` (Seurat rasterises
automatically above 1e5 cells) or build with `scattermore::geom_scattermore()`.
