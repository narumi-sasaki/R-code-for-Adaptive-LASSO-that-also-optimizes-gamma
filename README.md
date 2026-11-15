# R-code-for-Adaptive-LASSO-that-also-optimizes-gamma
ALASSO.R was developed for variable selection in large-scale experimental data collected according to a D-optimal design assuming a quadratic model. 
In the first stage, Elastic Net with model selection based on the LOOCV criterion is used, with hyperparameters determined via Bayesian optimization.
In the second stage, LASSO with model selection based on the BIC criterion is used, with hyperparameters determined via Bayesian optimization.
The selected variables need to be separately modeled while taking hierarchy (heredity) into account, as necessary.
For sample data and analysis details, please refer to the appendix of this book.
https://www.juse-p.co.jp/products/view/1066
