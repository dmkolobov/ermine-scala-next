package com.clarifi.reporting.util

import java.io.{InputStream, OutputStream}
import org.apache.log4j.Logger

sealed abstract class LogType()
case class ErrorLog() extends LogType
case class InfoLog() extends LogType
case class DebugLog() extends LogType

class StreamLogger(val inStream:InputStream, val logger:Logger, logType:LogType) extends Thread {
  val buf = new Array[Byte](1000)
  val logFunc:Function1[String,Unit] = logType match {
    case ErrorLog() => logger.error _
    case InfoLog() => logger.info _
    case DebugLog() => logger.debug _
    case _ => throw new IllegalArgumentException("Unrecognized log type:" + logType)
  }

  override def run(): Unit = {
    var num = 0
    while (num != -1) {
      num = inStream.read(buf, 0, buf.length)
      if (num != -1) {
        val str = new StringBuilder()
        while (num != 0) {
          str.append(new String(buf, 0, num))
          num = inStream.read(buf, 0, math.min(inStream.available(), buf.length)) //non-blocking read--don't block if we happened to read it all
        }

        logFunc (str.toString.trim)
      }
    }
  }
}
