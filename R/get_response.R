#' Get Response from OpenAI Chat API
#'
#' This function sends a user input to the OpenAI Chat API and retrieves a response.
#'
#' @param user_input The user's input for the chat interaction. Default is "what is a p-value in statistics?".
#' @param system_specification The system's role and content for the chat interaction. Default is "You are a helpful assistant.".
#' @param model The OpenAI language model to use. Default is "gpt-3.5-turbo".
#' @param api_key The API key for accessing the OpenAI API. Defaults to the value of the "OPENAI_API_KEY" environment variable.
#' @param print_response Logical, indicating whether to print the response. Default is TRUE.
#'
#' @return A list containing the response from the OpenAI Chat API.
#'
#' @examples
#' response1 = get_response(user_input = "How to calculate the bonforoni corrected p values?")
#' response2 = get_response(user_input = paste0("Based on this data.frame in R: \n\n",
#'                                             dataframe_to_text(mtcars),
#'                                             "\n\n which variables are correlated?"))
#'response3 = get_response(user_input = "What are redox reactions?",
#'                         system_specification = "You are a knowledgeable and helpful chemist \n
#'                         who will answer any questions in German")
#'
#' @importFrom jsonlite fromJSON
#' @importFrom RCurl getURL
#'
#' @export

get_response = function(user_input = "what is a p-value in statistics?",
                        system_specification = "You are a helpful assistant.",
                        model = "gpt-3.5-turbo",
                        api_key = Sys.getenv("OPENAI_API_KEY"),
                        print_response = TRUE){
  
  user_input = gsub(pattern = "\n", replacement = "", user_input)
  system_specification = gsub(pattern = "\n", replacement = "", system_specification)
  
  url = "https://api.openai.com/v1/chat/completions"
  headers = c(
    "Authorization" = paste0("Bearer ", api_key),
    "Content-Type" = "application/json"
  )
  
  data = paste0('{"model": "gpt-3.5-turbo", "messages": [
          {"role": "system", "content": "', system_specification, '"},
          {"role": "user", "content": "', user_input, '"}
          ]}')
  
  result = getURL(url, httpheader = headers, postfields = data)
  result = fromJSON(result)
  
  if(print_response){
    if(!is.null(result$choices$message$content)){
      cat(result$choices$message$content)
    }
  }
  
  return(result)
  
}








