############################################################
# Load packages
############################################################
library(gcdnet)
library(foreach)
library(bbotk)
library(mlr3)
library(mlr3mbo)
library(mlr3learners)

############################################################
# 1. Load data
############################################################
df_yX <- read.csv("train_data.csv", stringsAsFactors = FALSE)
Y     <- as.matrix(df_yX[,  1, drop = FALSE])  # Response
X     <- as.matrix(df_yX[, -1])                # Factors including higher-order terms
n_obs <- nrow(X)

############################################################
# 2. Cross-validation indices (for Elastic Net LOOCV)
############################################################
set.seed(0)
n_folds <- n_obs
foldid  <- sample(seq_len(n_folds))  # One fold per observation (LOOCV)

############################################################
# 3. Function definitions
############################################################

# For Elastic Net (both lambda1 and lambda2 are cross-validated)
gcdCV <- function(funX, loglambda1, loglambda2, funpf) {
  mean(
    foreach(
      i         = seq_len(n_folds),
      .export   = c("funX", "funpf", "foldid", "n_folds", "Y",
                    "loglambda1", "loglambda2"),
      .packages = "gcdnet",
      .combine  = "c"
    ) %do% {
      train_idx <- foldid != i
      valid_idx <- !train_idx
      
      fit <- gcdnet(
        funX[train_idx, ], Y[train_idx],
        lambda    = 10 ^ loglambda1,
        lambda2   = 10 ^ loglambda2,
        pf        = funpf,
        method    = "ls"
      )
      
      ypred <- predict(fit, funX[valid_idx, , drop = FALSE])
      mean((ypred - Y[valid_idx]) ^ 2)
    }
  )
}

# For Adaptive Lasso (lambda2 fixed at 0, BIC criterion)
AlassoBIC <- function(funX, loglambda1, funpf) {
  fit   <- gcdnet(
    funX, Y,
    lambda  = 10 ^ loglambda1,
    lambda2 = 0,
    pf      = funpf,
    method  = "ls"
  )
  devsq <- sum((predict(fit, funX) - Y) ^ 2)
  BIC   <- n_obs * (log(2 * pi * devsq / n_obs) + 1) +
    log(n_obs) * (sum(fit$beta[, 1] != 0) + 1)
  return(BIC)
}

############################################################
# 4. Initial estimate via Elastic Net (w_enet)
############################################################
set.seed(301)

obfun_enet <- ObjectiveRFun$new(
  fun = function(xs) {
    list(
      y = gcdCV(
        funX       = X,
        loglambda1 = xs$loglambda1,
        loglambda2 = xs$loglambda2,
        funpf      = rep(1, ncol(X))
      )
    )
  },
  domain   = ps(
    loglambda1 = p_dbl(-50, 50),
    loglambda2 = p_dbl(-50, 50)
  ),
  codomain = ps(y = p_dbl(tags = "minimize"))
)

terminator_enet  <- trm("evals", n_evals = 150)
instance_enet    <- OptimInstanceSingleCrit$new(
  objective  = obfun_enet,
  terminator = terminator_enet
)

design_enet <- generate_design_lhs(obfun_enet$domain, 100)$data
instance_enet$eval_batch(design_enet)

surrogate_enet <- SurrogateLearner$new(
  lrn("regr.km", control = list(trace = FALSE))
)
acqfun_enet <- AcqFunctionEI$new()
acqopt_enet <- AcqOptimizer$new(
  opt("random_search", batch_size = 100),
  terminator = trm("evals", n_evals = 100)
)

optimizer_enet <- opt(
  "mbo",
  loop_function = bayesopt_ego,
  surrogate     = surrogate_enet,
  acq_function  = acqfun_enet,
  acq_optimizer = acqopt_enet
)

w_enet <- optimizer_enet$optimize(instance_enet)

w_enet.opt <- gcdnet(
  X, Y,
  lambda    = 10 ^ w_enet$loglambda1,
  lambda2   = 10 ^ w_enet$loglambda2,
  method    = "ls",
  intercept = TRUE
)

# Extract variables with nonzero coefficients
nonzero_idx <- as.vector(w_enet.opt$beta != 0)
newX        <- X[, nonzero_idx, drop = FALSE]

# Standard deviations used for computing weights
stdev <- apply(X, 2, sd)

############################################################
# 5. Adaptive Lasso (aenet)
############################################################
if (sum(nonzero_idx) > 1) {
  set.seed(301)
  
  obfun_alasso <- ObjectiveRFun$new(
    fun = function(xs) {
      weights_all     <- (abs(as.numeric(w_enet.opt$beta) * stdev) + 1 / n_obs) ^ (-xs$gamma_ctrl)
      weights_nonzero <- weights_all[nonzero_idx]
      list(
        y = AlassoBIC(
          funX       = newX,
          loglambda1 = xs$loglambda1,
          funpf      = weights_nonzero
        )
      )
    },
    domain   = ps(
      loglambda1 = p_dbl(-50,  50),
      gamma_ctrl = p_dbl(-50, 100)
    ),
    codomain = ps(y = p_dbl(tags = "minimize"))
  )
  
  terminator_alasso <- trm("evals", n_evals = 150)
  instance_alasso   <- OptimInstanceSingleCrit$new(
    objective  = obfun_alasso,
    terminator = terminator_alasso
  )
  
  design_alasso <- generate_design_lhs(obfun_alasso$domain, 100)$data
  instance_alasso$eval_batch(design_alasso)
  
  surrogate_alasso <- SurrogateLearner$new(
    lrn("regr.km", control = list(trace = FALSE))
  )
  acqfun_alasso <- AcqFunctionEI$new()
  acqopt_alasso <- AcqOptimizer$new(
    opt("random_search", batch_size = 100),
    terminator = trm("evals", n_evals = 100)
  )
  
  optimizer_alasso <- opt(
    "mbo",
    loop_function = bayesopt_ego,
    surrogate     = surrogate_alasso,
    acq_function  = acqfun_alasso,
    acq_optimizer = acqopt_alasso
  )
  
  aenet <- optimizer_alasso$optimize(instance_alasso)
  
  # Final model (lambda2 = 0)
  weights_all     <- (abs(as.numeric(w_enet.opt$beta) * stdev) + 1 / n_obs) ^ (-aenet$gamma_ctrl)
  weights_nonzero <- weights_all[nonzero_idx]
  
  aenet.opt <- gcdnet(
    newX, Y,
    lambda    = 10 ^ aenet$loglambda1,
    lambda2   = 0,
    method    = "ls",
    intercept = TRUE,
    pf        = weights_nonzero
  )
  
  coef_alasso   <- as.matrix(aenet.opt$beta)
  coef_selected <- t(as.data.frame(coef_alasso))
  all_vars      <- c("(Intercept)", colnames(X))
  
  AlassoBIC_beta                    <- setNames(rep(0, length(all_vars)), all_vars)
  AlassoBIC_beta["(Intercept)"]     <- aenet.opt$b0
  AlassoBIC_beta[colnames(coef_selected)] <- coef_selected
  
} else {
  # If the number of nonzero coefficients is 1 or fewer, use the Elastic Net result as-is
  all_vars <- c("(Intercept)", colnames(X))
  
  AlassoBIC_beta                <- setNames(rep(0, length(all_vars)), all_vars)
  AlassoBIC_beta["(Intercept)"] <- w_enet.opt$b0
  AlassoBIC_beta[colnames(X)]   <- as.vector(w_enet.opt$beta)
}

############################################################
# 6. Aggregate and export results
############################################################
data_summary           <- cbind(AlassoBIC = AlassoBIC_beta)
rownames(data_summary) <- c("(Intercept)", colnames(X))
write.csv(data_summary, "ALASSO_summary.csv")
