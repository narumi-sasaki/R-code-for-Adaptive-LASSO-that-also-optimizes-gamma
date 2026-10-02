# ■ R Package Installation Guide for Beginners: Proxy Setup & Rtools-Free Installation

This guide explains how to smoothly install R packages in a secured corporate network (proxy environment). 
Please follow these three steps in order, while running the code below in your R console.

If your company prohibits using credentials in proxy URLs (e.g., http://user:password@proxy), 
or blocks direct outbound connections via proxy, you may be required to install packages 
exclusively through your company's dedicated private repository (e.g., Artifactory, 
Posit/RStudio Package Manager).

If this applies to your corporate environment, please SKIP Step 1 entirely and 
PROCEED DIRECTLY TO "Step 2-2. Set Repository and Timeout Settings" to configure 
your internal repository address.

## 【Step 1: Get and Set Proxy Server Information】

### 1-1. Check Proxy Server Information (For Windows Users)
Retrieve the currently configured proxy server address and port from the Windows Registry. Please retrieve your proxy server address and port from either proxy$ProxyServer or proxy$AutoConfigURL.
If the curl package is available, run the following command and use the returned proxy address and port:
　curl::ie_get_proxy_for_url("https://cloud.r-project.org/")

```r
proxy <- utils::readRegistry(
  "Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
  hive = "HCU"
)

proxy[c("ProxyEnable", "ProxyServer", "ProxyOverride", "AutoConfigURL")]
```

*Note for macOS/Linux Users:
The command above is for Windows only. If you are using macOS or Linux, please check your system network settings or ask your IT department to find your proxy server address and port.


### 1-2. Configure Environment Variables
Replace "user_ID:password" and "ooo" (your proxy server address and port) with your actual information, and run the following code. In place of 'ooo', please input either the socket address or the URL (excluding the 'http://' prefix).

```r
Sys.setenv(http_proxy  = "http://user_ID:password@ooo")
Sys.setenv(https_proxy = "http://user_ID:password@ooo")
```

*Note: 
If your password contains special characters such as "@", "/", or "\", you must URL-encode those characters beforehand. Please search web tools for "URL encoder" if needed.


【Step 2: Connection Test and Network Configuration】

### 2-1. Test the Connection
Verify if you can access external websites through the proxy. Run the following code; if the status code returns "200", your connection is working properly.

```r
res <- curlGetHeaders("https://cloud.r-project.org/")
attr(res, "status")
```

### 2-2. Set Repository and Timeout Settings
Start a fresh R session and run the following commands. This resets your connection target to the global CRAN cloud (via CDN) and extends the network timeout to 10 minutes (600 seconds) to handle slow connections.

```r
options(repos = c(CRAN = "https://cloud.r-project.org"))
options(timeout = 600)
```

*Note: 
Depending on your corporate infrastructure restrictions, you may need to specify the address of an internal, company-dedicated repository (CRAN mirror). 

*Note on CRAN Mirror Selection:
If the global CRAN cloud is unstable or blocked by your corporate firewall, you can replace the URL with a reliable local CRAN mirror located in your country or your company's private repository.


## 【Step 3: Install Packages Specifying Binary Format】

### 3-1. Install the Package
When installing packages, always append 'type = "binary"' to the command. Below is an example using the "gcdnet" package.

```r
install.packages("gcdnet", type = "binary")
```

# ■ Why Specifying 'type = "binary"' Is Crucial

- It allows instant installation without requiring a compiler environment (Rtools).
- In secured corporate networks, attempting to build a package from source code often fails. This is because security restrictions may block the retrieval of additional files required during compilation.
- By default, R will attempt to build from source if a newer version is available. Specifying binary format suppresses this behavior, ensuring a safe and successful installation of the stable, pre-compiled binary version.
