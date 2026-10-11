# R-code-for-Adaptive-LASSO-that-also-optimizes-gamma
ALASSO.R was developed for variable selection in large-scale experimental data collected according to a D-optimal design assuming a quadratic model. 
In the first stage, Elastic Net with model selection based on the LOOCV criterion is used, with hyperparameters determined via Bayesian optimization.
In the second stage, LASSO with model selection based on the BIC criterion is used, with hyperparameters determined via Bayesian optimization.
The selected variables need to be separately modeled while taking hierarchy (heredity) into account, as necessary.
For sample data and analysis details, please refer to the appendix of this book.
https://www.juse-p.co.jp/products/view/1066

Random numbers are used in the Bayesian optimization for hyperparameter selection in both the first-stage Elastic Net and the second-stage LASSO.
Although a random seed of 301 is specified for both stages in ALASSO.R, the results may still vary depending on the computational environment.
Since variables with relatively weak effects may be selected inconsistently across different random seeds, performing the stability evaluation is highly recommended.
Although the stability evaluation is computationally intensive, it can help identify variables that are consistently selected across repeated analyses.
To perform the stability evaluation, please execute "ALASSO_Stability_Evaluation.R".
However, please note that the selected explanatory variables must be evaluated based on domain knowledge and validated through physical experiments to confirm reproducibility.
