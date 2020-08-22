#'Starting the R server for StatsNotebook
#'This function starts the R server. Future implementation will allow change of port
#'Use "off" to turn off server


#' @export
start_server <- function() {

  text_handler <- function(x) {
    OutputJSON <- list(OutputType = "Normal", toBlk = CodesJSON$fromBlk, Output = x)
    OutputString <- jsonlite::toJSON(OutputJSON, digits = NA)
    OutputString <- utf8::utf8_normalize(OutputString, map_quote=TRUE)
    pbdZMQ::zmq.msg.send(charToRaw(OutputString), ReplyToNode, flags = .pbd_env$ZMQ.SR$BLOCK,serialize = FALSE)
  }

  graphics_handler <- function(x) {
    png_bin <- repr::repr_png(x)
    Output <- base64enc::base64encode(png_bin)
    OutputJSON <- list(OutputType = "Graphics", toBlk = CodesJSON$fromBlk, Output = Output)
    OutputString <- jsonlite::toJSON(OutputJSON, digits = NA)
    pbdZMQ::zmq.msg.send(charToRaw(OutputString), ReplyToNode, flags = .pbd_env$ZMQ.SR$BLOCK,serialize = FALSE)
  }

  warning_handler <- function(x) {
    message <- conditionMessage(x)
    message <- paste0("Warning message: ",message,"\n")
    OutputJSON <- list(OutputType = "Warning", toBlk = CodesJSON$fromBlk, Output = message)
    OutputString <- jsonlite::toJSON(OutputJSON, digits = NA)
    OutputString <- utf8::utf8_normalize(OutputString, map_quote=TRUE)
    pbdZMQ::zmq.msg.send(charToRaw(OutputString), ReplyToNode, flags = .pbd_env$ZMQ.SR$BLOCK,serialize = FALSE)
  }

  message_handler <- function(x) {
    message <- conditionMessage(x)
    message <- paste0("Message: ",message, "\n")
    OutputJSON <- list(OutputType = "Message", toBlk = CodesJSON$fromBlk, Output = message)
    OutputString <- jsonlite::toJSON(OutputJSON, digits = NA)
    OutputString <- utf8::utf8_normalize(OutputString, map_quote=TRUE)
    pbdZMQ::zmq.msg.send(charToRaw(OutputString), ReplyToNode, flags = .pbd_env$ZMQ.SR$BLOCK,serialize = FALSE)
  }

  error_handler <- function(x) {
    message <- conditionMessage(x)
    message <- paste0("Error: ",message, "\n")
    OutputJSON <- list(OutputType = "Error", toBlk = CodesJSON$fromBlk, Output = message)
    OutputString <- jsonlite::toJSON(OutputJSON, digits = NA)
    OutputString <- utf8::utf8_normalize(OutputString, map_quote=TRUE)
    pbdZMQ::zmq.msg.send(charToRaw(OutputString), ReplyToNode, flags = .pbd_env$ZMQ.SR$BLOCK,serialize = FALSE)
  }

  varType <- function(x) {
    if (is.numeric(x)) {
      return("Numeric")
    }
    if (is.character(x)) {
      return("Character")
    }
    if (is.factor(x)) {
      return("Factor")
    }
    if (lubridate::is.Date(x)) {
      return("Date")
    }
  }

  ZmqContext <- pbdZMQ::zmq.ctx.new()
  RequestFromNode <- pbdZMQ::zmq.socket(ZmqContext, .pbd_env$ZMQ.ST$ROUTER)
  ReplyToNode <- pbdZMQ::zmq.socket(ZmqContext, .pbd_env$ZMQ.ST$DEALER)

  pbdZMQ::zmq.bind(RequestFromNode,"tcp://*:5556")
  pbdZMQ::zmq.connect(ReplyToNode, "tcp://localhost:5555")

  counter = 0

  output_handler <- evaluate::new_output_handler(
    source = identity,
    text = text_handler,
    graphics = graphics_handler,
    message = message_handler,
    warning = warning_handler,
    error = error_handler)

  server_on <- TRUE
  CodesString <- NULL
  CodesJSON <- NULL
  output <- NULL
  handler <- NULL
  OutputJSON <- NULL
  OutputString <- NULL
  CategoricalVarLevels <- NULL



  while (server_on) {
    RawCodes <- pbdZMQ::zmq.recv.multipart(RequestFromNode, unserialize = FALSE)
    CodesString <- rawToChar(RawCodes[[2]])
    CodesJSON <- jsonlite::fromJSON(CodesString)
    print(paste0("Codes received: ", CodesJSON$Script))
    print(paste0("From Block: ", CodesJSON$fromBlk))
    print(paste0("Request Type: ", CodesJSON$RequestType))

    if (stringr::str_detect(CodesJSON$Script,"currentDataset <- read_csv\\(") ||
        stringr::str_detect(CodesJSON$Script,"currentDataset <- read_sav\\(") ||
        stringr::str_detect(CodesJSON$Script,"currentDataset <- read_dta\\("))
    {
      if (exists("originalDataset")) {
        rm("originalDataset")
      }
    }

    if (CodesJSON$RequestType == "RCode") {
      if (CodesJSON$Script == "off")
      {
        server_on = FALSE
      }else {
        internal_res <- evaluate::evaluate(CodesJSON$Script, output_handler = output_handler, envir = .GlobalEnv)
        OutputJSON <- list(OutputType = "END", toBlk = CodesJSON$fromBlk, Output = "")
        OutputString <- jsonlite::toJSON(OutputJSON)
        pbdZMQ::zmq.msg.send(charToRaw(OutputString), ReplyToNode, flags = .pbd_env$ZMQ.SR$BLOCK,serialize = FALSE)
      }
    }else if (CodesJSON$RequestType == "getVariableList") {
      if (!is.null(get0("currentDataset"))) {
        if (is.data.frame(currentDataset)) {
          CategoricalVarLevels = lapply(subset(currentDataset, select = sapply(currentDataset, is.factor)), levels)
          CategoricalVarLevels = CategoricalVarLevels[order(names(CategoricalVarLevels))]
          OutputJSON <- list(OutputType = "getVariableList", toBlk = "", Output = lapply(currentDataset, varType),
                             CategoricalVarLevels = CategoricalVarLevels)
          OutputString <- jsonlite::toJSON(OutputJSON)
        }else
        {
          OutputString <- '{"OutputType":["getVariableList"],"toBlk":[""],"Output":[]}'
        }
        pbdZMQ::zmq.msg.send(charToRaw(OutputString), ReplyToNode, flags = .pbd_env$ZMQ.SR$BLOCK,serialize = FALSE)
      }else
      {
        print("Load the data first")
      }
    }else if (CodesJSON$RequestType == "getData") {
      if (!is.null(get0("currentDataset"))) {
        if (is.data.frame(currentDataset)) {
          if (nrow(currentDataset) > 500) {
            tmpDataset = head(currentDataset, 500)
          }else
          {
            tmpDataset = currentDataset
          }
          OutputJSON <- list(OutputType = "getData", toBlk = "", Output = tmpDataset, nrow = nrow(tmpDataset), ncol = ncol(tmpDataset))
          OutputString <- jsonlite::toJSON(OutputJSON)
        }else {
          OutputString <- '{"OutputType":["getData"],"toBlk":[""],"Output":[]}'
        }
        pbdZMQ::zmq.msg.send(charToRaw(OutputString), ReplyToNode, flags = .pbd_env$ZMQ.SR$BLOCK,serialize = FALSE)
      }else
      {
        print("Load the data first")
      }
    }

  }

  pbdZMQ::zmq.close(RequestFromNode)
  pbdZMQ::zmq.close(ReplyToNode)
  pbdZMQ::zmq.ctx.destroy(ZmqContext)
}

