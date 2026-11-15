library(gcdnet)

############################################################
# 1. Load data
############################################################
df_yX <- read.csv("train_data.csv", stringsAsFactors = FALSE)
y     <- as.numeric(df_yX[, 1])      # Response
X     <- as.matrix(df_yX[, -1])      # Factors including higher-order terms
n_obs <- nrow(X)

############################################################
# 2. Search grids
############################################################
lambda2_grid <- c(0, 10 ^ seq(-4, 1, by = 0.1))   # Elastic Net lambda2
gamma_grid   <- seq(0.5, 3, by = 0.25)            # Adaptive Lasso gamma
tie_tol      <- 1e-8                              # tolerance for ties

# lambda1 path of Stage 1: 4 decades below the data-driven maximum
lambda1_max  <- 2 * max(gcdnet(X, y, method = "ls", lambda2 = 0,
                               nlambda = 5)$lambda)
lambda1_grid <- 10 ^ seq(log10(lambda1_max), log10(lambda1_max) - 4,
                         length.out = 200)

############################################################
# 3. Stage 1: Elastic Net (LOOCV)
############################################################
# LOOCV mean squared error for every (lambda1, lambda2)
cvm <- sapply(lambda2_grid, function(lambda2) {
  err <- sapply(seq_len(n_obs), function(i) {
    fit <- gcdnet(X[-i, , drop = FALSE], y[-i], lambda = lambda1_grid,
                  lambda2 = lambda2, method = "ls")
    (as.numeric(predict(fit, newx = X[i, , drop = FALSE])) - y[i]) ^ 2
  })
  rowMeans(err)
})

# Minimum; ties -> largest lambda1, then largest lambda2
cand <- which(cvm <= min(cvm) + tie_tol * max(1, abs(min(cvm))),
              arr.ind = TRUE)
cand <- cand[order(cand[, 1], -cand[, 2]), , drop = FALSE]
i1   <- cand[1, 1]
i2   <- cand[1, 2]

fit_enet  <- gcdnet(X, y, lambda = lambda1_grid,
                    lambda2 = lambda2_grid[i2], method = "ls")
beta_enet <- as.numeric(fit_enet$beta[, i1])

# Variables with nonzero coefficients
nonzero_idx <- beta_enet != 0
newX        <- X[, nonzero_idx, drop = FALSE]

############################################################
# 4. Stage 2: Adaptive Lasso (BIC)
############################################################
all_vars       <- c("(Intercept)", colnames(X))
AlassoBIC_beta <- setNames(rep(0, length(all_vars)), all_vars)

if (sum(nonzero_idx) > 1) {

  # Base of the adaptive weights (standardized Elastic Net coefficients)
  base_weight <- (abs(beta_enet * apply(X, 2, sd)) + 1 / n_obs)[nonzero_idx]

  best_bic <- Inf
  for (gamma in gamma_grid) {
    pf <- base_weight ^ (-gamma)
    pf <- pf / mean(pf)

    # lambda1 path, widened according to the spread of the weights
    lmax    <- 2 * max(gcdnet(newX, y, pf = pf, lambda2 = 0, method = "ls",
                              nlambda = 5)$lambda)
    decades <- min(4 + log10(max(pf) / min(pf)), 12)
    lambda1_path <- 10 ^ seq(log10(lmax), log10(lmax) - decades,
                             length.out = max(50, ceiling(decades * 50)))

    fit <- gcdnet(newX, y, lambda = lambda1_path, lambda2 = 0,
                  pf = pf, method = "ls")
    rss <- colSums((as.matrix(predict(fit, newx = newX)) - y) ^ 2)
    df  <- colSums(as.matrix(fit$beta) != 0)
    bic <- n_obs * (log(2 * pi * rss / n_obs) + 1) + log(n_obs) * (df + 1)
    bic[df > n_obs - 2 | !is.finite(bic)] <- Inf

    # Ties: largest lambda1 within a path, smallest gamma across paths
    k <- which(bic <= min(bic) + tie_tol * max(1, abs(min(bic))))[1]
    if (bic[k] < best_bic - tie_tol * max(1, abs(bic[k]))) {
      best_bic <- bic[k]
      AlassoBIC_beta["(Intercept)"]  <- fit$b0[k]
      AlassoBIC_beta[colnames(newX)] <- fit$beta[, k]
    }
  }

} else {
  # One or no nonzero coefficient: use the Elastic Net result as-is
  AlassoBIC_beta["(Intercept)"] <- fit_enet$b0[i1]
  AlassoBIC_beta[colnames(X)]   <- beta_enet
}

############################################################
# 5. Export results
############################################################
data_summary <- cbind(AlassoBIC = AlassoBIC_beta)
write.csv(data_summary, "ALASSO_summary.csv")
