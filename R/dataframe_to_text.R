#' Convert data.frams to text interpretable by ChatGPT
#'
#' This function takes a dataframe as input and converts it to a text representation.
#'
#' @param dataframe A dataframe to be converted.
#'
#' @return A character vector representing the dataframe in text format.
#'
#' @examples
#' dataframe <- data.frame(
#'   Name = c("John", "Alice", "Bob"),
#'   Age = c(25, 30, 22),
#'   Score = c(95, 88, 75)
#' )
#' dataframe_to_text(dataframe)
#'
#' @export

dataframe_to_text = function(dataframe){
  column_names = names(dataframe)
  row_names = rownames(dataframe)
  content = as.character(dataframe)
  
  dataframe_text = paste(
    paste("Column Names: ", paste(column_names, collapse = ", ")),
    paste("Row Names: ", paste(row_names, collapse = ", ")),
    paste(paste(column_names, content, sep = " = "), collapse = "\n"),
    sep = "\n\n"
  )
  
  dataframe_text = gsub(pattern = "\n", replacement = "", dataframe_text)
  return(dataframe_text)
}