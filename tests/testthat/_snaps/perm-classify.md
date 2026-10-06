# printing a risk lists the flagged calls; displays escape controls (IC-53)

    Code
      print(r)
    Output
      risk 3 (dangerous)
        [3] file_delete  unlink("data", recursive = TRUE) [path: workspace]
        creates: df, res

