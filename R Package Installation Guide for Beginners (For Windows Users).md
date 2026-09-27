# ■ R Package Installation Guide for Beginners: Proxy Setup & Rtools-Free Installation

This guide explains how to smoothly install R packages in a secured corporate network (proxy environment). 
Please follow these three steps in order, while running the code below in your R console.


## 【Step 1: Get and Set Proxy Server Information】

### 1-1. Check Proxy Server Information (For Windows Users)
Retrieve the currently configured proxy server address and port from the Windows Registry. 

```r
readRegistry("Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings", "HCU")$ProxyServer
```

*Note for macOS/Linux Users:
The command above is for Windows only. If you are using macOS or Linux, please check your system network settings or ask your IT department to find your proxy server address and port.


### 1-2. Configure Environment Variables
Replace "user_ID:password" and "ooo" (your proxy server address and port) with your actual information, and run the following code.

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
res <- curlGetHeaders("http://www.google.com/")
attr(res, "status")
```

*Note for Specific Regions:
If Google is blocked in your country or region (e.g., in China), please replace "http://www.google.com/" with a locally accessible major website (e.g., "http://www.baidu.com/").


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
