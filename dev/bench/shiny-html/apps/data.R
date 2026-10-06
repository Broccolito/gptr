set.seed(1)
sales = data.frame(region = sample(c("North", "South", "East", "West"), 5000, TRUE),
                   month = factor(sample(month.abb, 5000, TRUE), levels = month.abb),
                   units = rpois(5000, 40), price = round(runif(5000, 5, 50), 2))
sales$revenue = sales$units * sales$price
cars_df = cbind(name = rownames(mtcars), mtcars)
rownames(cars_df) = NULL
inv_a = data.frame(product = c("apple", "banana", "cherry", "date", "elderberry", "fig", "grape", "honeydew"),
                   price = c(1.2, 0.5, 3.75, 2.4, 5.1, 2.25, 1.8, 3.3),
                   stock = c(120, 300, 45, 80, 20, 60, 150, 35))
inv_b = data.frame(product = c("kiwi", "lemon", "mango", "nectarine", "orange", "papaya", "quince", "raspberry"),
                   price = c(0.9, 0.6, 1.95, 1.4, 0.75, 2.8, 2.1, 4.5),
                   stock = c(200, 250, 90, 110, 400, 30, 25, 70))
