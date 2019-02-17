#-------------------------------------------#
# Part of R-package meteogrid               #
# Copyright (c) 2003-2018 Alex Deckmyn      #
#   Royal Meteorological Institute, Belgium #
# alex.deckmyn@meteo.be                     #
# Released under GPL-3 license              #
#-------------------------------------------#
is.geofield <- function(x){
  inherits(x,"geofield")
}

print.geofield <- function(x, ...){
  cat(paste(attr(x, "info")$origin, ":", attr(x, "info")$name), "\n")
  if (length(dim(x)) > 2) {
    cat("Extra dimensions: ", paste(names(dim(x)), dim(x), sep="=", collapse=", "), "\n")
  }
  cat("Time:\n")
  cat(attr(x,"time"),"\n")
  cat("Domain summary:\n")
  print(attr(x,"domain"))
  cat("Data summary:\n")
  cat(summary(as.vector(x)),"\n")
}

as.geofield <- function (x=NA, domain, time = attr(domain, "time"),
                         info = attr(domain, "info"),
                         extra_dim=list()) {
  mydomain <- as.geodomain(domain)
  if (is.geofield(x)) return(x)

  # fix the dimensions  
  if (!is.list(extra_dim)) {
    dims <- c("x"=mydomain$nx, "y"=mydomain$ny, extra_dim)
    extra_dim <- lapply(extra_dim, function(x) 1:x)
    dimnam <- NULL
  } else {
    dims <- c("x"=mydomain$nx, "y"=mydomain$ny, 
              vapply(extra_dim, FUN=length, FUN.VALUE=1))
    if (length(dims) == 2) dimnam <- NULL
    else dimnam <- c(list("x"=NULL, "y"=NULL), extra_dim)
  }

  if (is.vector(x)) {
    x <- array(x, dim=dims)
  } else {
    ### the array is already provided
    ### so any extra dimensions are only passed to supply dimension names
    ### if they are not given, we can try whether x already has dimnames
    if (length(extra_dim)==0) {
      dims <- c(dims, dim(x)[-(1:2)])
      dimnam <- dimnames(x)
    }
    # check all dimensions
    if (any(dim(x) != dims)) stop("Wrong dimensions.", 
			     paste(dim(x), collapse=" x "), " vs ",
			     paste(dims, collapse=" x "))
  }
  noname <- which(is.na(names(dims)) | names(dims)=="" )
  names(dims)[noname] <- paste0("D", noname)
  names(dim(x)) <- names(dims)
  # also set dimnames (not for x,y!)
  # after names(dim(x)) <- , dimnames is always reset to NULL !
  dimnames(x) <- dimnam

  attr(x, "domain") <- mydomain
  attr(x, "time")   <- time
  attr(x, "info")   <- if (is.null(info)) list() else info
  class(x) <- "geofield"
  return(x)
}


# a simple method for >2d geofields using x[[i,j...]]
# max 3 extra dimensions are allowed (e.g. time, level, members).
# ATTENTION: with 2 extra dimensions z[[n]] gives z[[n,]]
#            it should throw an error
# but that is (almost?) impossible to solve with R code
# e.g. ellipsis (...) can't deal with empty dimensions
# I guess that's exactly why "[" is a primitive
.subset.geofield <- function(x, i, j, k) {
  dimx <- length(dim(x))
  if (dimx <= 2) stop("Subsetting a geofield requires extra dimensions")
  if ( (dimx < 5 && !missing(k)) || (dimx < 4 && !missing(j))) {
    stop("Bad dimensioning. Object has ", dimx-2, " extra dimensions.")
  }
  if (missing(i) && dimx >= 3) i <- 1:dim(x)[3]
  if (missing(j) && dimx >= 4) j <- 1:dim(x)[4]
  if (missing(k) && dimx >= 5) k <- 1:dim(x)[5]
  result <- as.geofield(switch(dimx - 2, x[,,i], x[,,i,j], x[,,i,j,k]),
			domain=x)
  info <- attr(result, "info")
  time <- attr(result, "time")
  if (is.null(info)) info <- list()
  if (is.null(time)) time <- NA_integer_
  # when dropping a dimension (e.g. length(i)=1), you fix a level/member/...
  # so that should be in the info field
  # TODO: fix this if you drop multiple dimensions!
  # ATTENTION: if there is a squashed dimension called "name", info$name will be overwritten!
  squashed <- list()
  if (dimx >= 3 && length(i)==1) {
    squashed[[names(dim(x))[3] ]] <- dimnames(x)[[3]][i]
    # supported z_types: level, mbr, hPa, m, ldt
#    if (!is.null(info$z_type)) {
#      info$name <- switch((info$z_type),
#              "mbr" = paste0(info$name, " mbr",i2a(dimnames(x)[[3]][i],3)),
#              "hPa" = paste0(info$name, " ",dimnames(x)[[3]][i], "hPa"),
#	      "level"=,
#              "hybrid" = paste0(info$name, " lev ",dimnames(x)[[3]][i]),
#              "m" = paste0(info$name, " ",dimnames(x)[[3]][i],"m"),
#              "ldt" = paste0(info$name, " +",dimnames(x)[[3]][i]),
#              "prm" = paste0(dimnames(x)[[3]][i]),
#	      info$name)
#    }
  }
  if (dimx >= 4 && length(j)==1) squashed[[names(dim(x))[4] ]] <- dimnames(x)[[4]][j]
  if (dimx >= 5 && length(k)==1) squashed[[names(dim(x))[5] ]] <- dimnames(x)[[5]][k]
  # we add the "squashed" dimension to the name or time tags (for e.g. iview)
  # use [[ ]] rather than $, because $m would also point at $mbr
  if (!is.null(squashed[["ldt"]]) ) {
    attr(time, "leadtime") <- as.numeric(squashed$ldt)
    # by assigning to time[1] you keep all attributes!
    time[1] <- sprintf("%s +%s", format(attr(time, "basedate"), "%Y/%m/%d %H:%M"), squashed$ldt)
    # TODO: fix leadtime scaling etc
    if (!is.null(attr(time, "basedate"))) {
      attr(time, "validdate") <- attr(time, "basedate") + as.numeric(squashed$ldt)
    }
  }
  # TODO: add other info fields like "level", "mbr"...
  if (!is.null(squashed[["prm"]])) info$name <- paste0(squashed$prm, info$name)
  if (!is.null(squashed[["hPa"]])) info$name <- paste0(info$name, " ", squashed[["hPa"]], "hPa")
  if (!is.null(squashed[["mbr"]])) info$name <- paste0(info$name, " mbr", squashed[["mbr"]])
  if (!is.null(squashed[["m"]])) info$name <- paste0(info$name, " ", squashed[["m"]], "m")

  attr(result, "info") <- info
  attr(result, "time") <- time
###  dimnames(result) <- c(list(x=NULL, y=NULL), extra_dim)
  result
}

# to make sum & mean over 3d geofields a bit faster (rowSums is much faste than apply(...,sum) )
# if you ever want to add more function: they should accept "dims=2"
apply_geo3d <- function(x, func="sum", newname=NULL, ...) {
  afun <- switch(func,
                 "sum" = rowSums,
                 "mean" = rowMeans,
                 # e.g. for wind speed :
                 "norm" = function(x, ...) sqrt(rowSums(x^2, ...)),
                 # wind direction (attention: in R, sign(0)=0, atan(x/0) == atan(x/"+0")
                 # We should have "sign(0)=1", so we use sign(1/u)
                 # because x/0.0 defaults to +Inf
                 "wdir" = function(x, ...) 
                   (-180 - atan(x[,,2]/x[,,1]) * 180/pi + sign(1/x[,,1] ) * 90) %% 360,
                 stop("Unknown function", func))

  if (!is.geofield(x) || length(dim(x)) != 3) stop("Only available for 3d geofields. dim=",
                                                   length(dim(x)))
  result <- as.geofield(afun(x, dims=2, ...), domain=x)
  if (!is.null(newname)) attr(result, "info")$name <- newname
  result
}


# ASSIGNMENT:
# MUCH HARDER: with missing dimensions, how do you find the data?
# only simple with 1 extra dimension
.subset.assign.geofield <- function(x, i, value) {
  dimx <- length(dim(x))
  if (dimx <= 2) stop("Subsetting a geofield requires extra dimensions")
  if (dimx > 3) stop("Please use standard subscripting [,,,] for geofield assignment.")
  x[,,i] <- value
  x
}

# Much harder : using x[,,i]
# there is no "[.default", so you need to "unclass"
# which I suppose makes an extra copy of the whole array
# very messy and buggy, because you can not detect errors
# AVOID
# -> this function is NOT exported as a S3method("[", geofield)
.geosub1 <- function(x,i,j,k,l,m, ..., drop) {
  dimx=length(dim(x))
  if (missing(i) && dimx >= 1) i <- 1:dim(x)[1]
  if (missing(j) && dimx >= 2) j <- 1:dim(x)[2]
  if (missing(k) && dimx >= 3) k <- 1:dim(x)[3]
  if (missing(l) && dimx >= 4) l <- 1:dim(x)[4]
  if (missing(m) && dimx >= 5) m <- 1:dim(x)[5]

  result <- switch(dimx, unclass(x)[i], unclass(x)[i,j],
         unclass(x)[i,j,k], unclass(x)[i,j,k,l],
         unclass(x)[i,j,k,l,m])
  if (missing(i) && missing(j)) result <- as.geofield(result, x)
  result
}

 