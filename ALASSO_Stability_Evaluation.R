################################################################################
# IMPORTANT NOTICE ON RANDOMNESS & STABILITY EVALUATION
################################################################################
# While running this script is computationally expensive and time-consuming,
# it helps assess the stability of variable selection across repeated analyses.
# The number of iterations for the stability evaluation is set to 100.
# Adjust the number of iterations as needed.
#
# Place ALASSO.R in the same folder before running this script.
#
# With a small sample size, some explanatory variables may not be selected
# in any iteration.
#
# As a practical guideline, selection frequency can be interpreted as follows.
#
# 80% or higher (0.80 - 1.00)
# Variables with highly stable selection
# These variables are consistently selected across different random seeds.
# They are strong candidates for inclusion in the final model.
#
# 50% or higher and less than 80% (0.50 - < 0.80)
# Variables with moderate selection stability (require careful consideration)
# These variables are selected with moderate stability.
# Their selection may be affected by correlations with other variables.
# Whether to include them should be determined based on domain knowledge,
# physical principles, and physical experiments to confirm reproducibility.
#
# Less than 50% (< 0.50)
# Variables with unstable selection
# Careful consideration is required before inclusion.

############################################################
# 1. Setup & Environment
############################################################
# # Source ALASSO.R to initialize the analysis environment
source("ALASSO.R")

# Specify the number of iterations for the stability evaluation
n_iterations = 100

# Generate reproducible seeds using a fixed master seed
set.seed(42)
seeds = sample.int(1e6, size = n_iterations)

stability_matrix = matrix(
  0, 
  nrow = length(seeds), 
  ncol = ncol(X), 
  dimnames = list(paste0("Seed_", seeds), colnames(X))
)

############################################################
# 2. Stability Evaluation Iterative Loop
############################################################
for (i in seq_along(seeds)) {
  seed_idx = seeds[i]
  message(sprintf(
    "Running Stability Evaluation iteration %d/%d (Seed: %d)...", 
    i, length(seeds), seed_idx
  ))
  
  # --- Step 2.1: Elastic Net with Bayes Opt (Dynamic Seed) ---
  set.seed(seed_idx)
  obfun_enet = ObjectiveRFun$new(
    fun = function(xs) {
      list(y = gcdCV(
        funX       = X, 
        loglambda1 = xs$loglambda1, 
        loglambda2 = xs$loglambda2, 
        funpf      = rep(1, ncol(X))
      ))
    },
    domain   = ps(loglambda1 = p_dbl(-50, 50), loglambda2 = p_dbl(-50, 50)),
    codomain = ps(y = p_dbl(tags = "minimize"))
  )
  
  instance_enet = OptimInstanceSingleCrit$new(
    objective  = obfun_enet, 
    terminator = trm("evals", n_evals = 150)
  )
  instance_enet$eval_batch(generate_design_lhs(obfun_enet$domain, 100)$data)
  
  optimizer_enet = opt(
    "mbo",
    loop_function = bayesopt_ego,
    surrogate     = SurrogateLearner$new(
      lrn("regr.km", control = list(trace = FALSE))
    ),
    acq_function  = AcqFunctionEI$new(),
    acq_optimizer = AcqOptimizer$new(
      opt("random_search", batch_size = 100), 
      terminator = trm("evals", n_evals = 100)
    )
  )
  
  w_enet = optimizer_enet$optimize(instance_enet)
  w_enet.opt = gcdnet(
    X, Y, 
    lambda    = 10 ^ w_enet$loglambda1, 
    lambda2   = 10 ^ w_enet$loglambda2, 
    method    = "ls", 
    intercept = TRUE
  )
  
  nonzero_idx = as.vector(w_enet.opt$beta[, 1] != 0)
  
  # --- Step 2.2: Adaptive Lasso (Dynamic Seed) ---
  if (sum(nonzero_idx) > 1) {
    set.seed(seed_idx)
    newX = X[, nonzero_idx, drop = FALSE]
    
    obfun_alasso = ObjectiveRFun$new(
      fun = function(xs) {
        weights_all = (abs(as.numeric(w_enet.opt$beta) * stdev) + 
                         1 / n_obs) ^ (-xs$gamma_ctrl)
        weights_nonzero = weights_all[nonzero_idx]
        list(y = AlassoBIC(
          funX       = newX, 
          loglambda1 = xs$loglambda1, 
          funpf      = weights_nonzero
        ))
      },
      domain   = ps(loglambda1 = p_dbl(-50, 50), gamma_ctrl = p_dbl(-50, 100)),
      codomain = ps(y = p_dbl(tags = "minimize"))
    )
    
    instance_alasso = OptimInstanceSingleCrit$new(
      objective  = obfun_alasso, 
      terminator = trm("evals", n_evals = 150)
    )
    instance_alasso$eval_batch(
      generate_design_lhs(obfun_alasso$domain, 100)$data
    )
    
    optimizer_alasso = opt(
      "mbo",
      loop_function = bayesopt_ego,
      surrogate     = SurrogateLearner$new(
        lrn("regr.km", control = list(trace = FALSE))
      ),
      acq_function  = AcqFunctionEI$new(),
      acq_optimizer = AcqOptimizer$new(
        opt("random_search", batch_size = 100), 
        terminator = trm("evals", n_evals = 100)
      )
    )
    
    aenet = optimizer_alasso$optimize(instance_alasso)
    
    weights_all = (abs(as.numeric(w_enet.opt$beta) * stdev) + 
                     1 / n_obs) ^ (-aenet$gamma_ctrl)
    weights_nonzero = weights_all[nonzero_idx]
    
    aenet.opt = gcdnet(
      newX, Y, 
      lambda    = 10 ^ aenet$loglambda1, 
      lambda2   = 0, 
      method    = "ls", 
      intercept = TRUE, 
      pf        = weights_nonzero
    )
    
    # Track the active features from this run
    selected_vars = colnames(newX)[as.vector(aenet.opt$beta[, 1] != 0)]
    stability_matrix[i, selected_vars] = 1
  } else {
    selected_vars = colnames(X)[nonzero_idx]
    stability_matrix[i, selected_vars] = 1
  }
}

############################################################
# 3. Aggregate Stability Evaluation Metrics
############################################################
stability_summary = data.frame(
  Variable            = colnames(X),
  Selection_Count     = colSums(stability_matrix),
  Selection_Frequency = colMeans(stability_matrix)
)
stability_summary = stability_summary[
  order(-stability_summary$Selection_Frequency), 
]

# Export the aggregated selection rate matrix
write.csv(
  stability_summary, 
  "ALASSO_Stability_Evaluation_summary.csv", 
  row.names = FALSE
)
message(
  "Stability Evaluation workflow finalized. ",
  "Results written to 'ALASSO_Stability_Evaluation_summary.csv'"
)
