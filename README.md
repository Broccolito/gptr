# gptr: An R Interface with the ChatGPT API

**gptr** is an R package that provides a convenient interface with the OpenAI ChatGPT API. It allows you to interact with ChatGPT, a powerful language model, for various natural language processing tasks.

The `gptr` R package makes talking to ChatGPT in R super easy. It helps researchers and data folks by simplifying the complicated stuff, like asking questions and getting answers. With `gptr`, you can use ChatGPT in R without any hassle, making it simpler for everyone to do cool things with language!

## Installation

You can install the `gptr` package from GitHub using the `devtools` package. Make sure you have `devtools` installed:

```R
install.packages("devtools")
```

Then, install `gptr`:

```R
devtools::install_github("Broccolito/gptr")
```

## Usage

### Setting up API Key

Before using the package, set your OpenAI API key using the `Sys.setenv` function:

```R
Sys.setenv(OPENAI_API_KEY = "your_openai_api_key_here")
```

### Example Usage

#### Get Response

```R
library(gptr)

# Example 1
response1 <- get_response(user_input = "How to calculate the bonforoni corrected p values?")

# Example 2
response2 <- get_response(user_input = paste0("Based on this data.frame in R: \n\n",
                                               dataframe_to_text(mtcars),
                                               "\n\n which variables are correlated?"))

# Example 3
response3 <- get_response(user_input = "What are redox reactions?",
                          system_specification = "You are a knowledgeable and helpful chemist who will answer any questions in German")
```

#### DataFrame to Text

```R
# Example: Convert mtcars DataFrame to text
dataframe_text <- dataframe_to_text(mtcars)
print(dataframe_text)
```

## Important Note

Make sure to handle your OpenAI API key securely. Do not expose it in your code or share it publicly. It's recommended to set it as an environment variable as shown above.

## Contribution

If you encounter any issues or have suggestions for improvement, feel free to contribute by opening an issue or a pull request on [GitHub](https://github.com/Broccolito/gptr). 
