package com.clarifi.reporting.writers

import scala.collection.immutable.List._
import scala.annotation.tailrec

import scalaz.std.tuple._;
import scalaz.syntax.bifunctor._;

object Markdown {

  sealed trait MStyleType
    case object MSBold extends MStyleType
    case object MSItal extends MStyleType
    case object MSStrike extends MStyleType
    // style for outdated information
    // can be shown e.g. greyed out
    case object MSOutdated extends MStyleType

  sealed trait MSyntax
    case class MPlain(content: String) extends MSyntax
    case class MStyle(style: MStyleType, inner: List[MSyntax]) extends MSyntax
    case class MLink(isImage: Boolean, inner: List[MSyntax], destination: String, title: Option[String]) extends MSyntax
    case class MColor(color: String) extends MSyntax



  //Simple recursive descent stack-based parser for our lightweight markdownish syntax
  //GB 11/2012
  def parseMarkdown(inp: String): List[MSyntax] = {
    var cxt: List[String] = List()

    @tailrec
    def parseToken(x: List[Char], res: List[Char]): (MSyntax, List[Char]) = {
      x match {
        case '\\' :: c :: cs => parseToken(cs, c :: res)
        case '~' :: '~' :: '~' :: cs if (cxt.headOption == Some("o~")) => {
           cxt = cxt.tail
          (MPlain(res.reverse.mkString), cs)
        }
        case '~' :: '~' :: cs if (cxt.headOption == Some("s~")) => {
           cxt = cxt.tail
          (MPlain(res.reverse.mkString), cs)
        }
        case '*' :: '*' :: cs if (cxt.headOption == Some("b*")) => {
          cxt = cxt.tail
          (MPlain(res.reverse.mkString), cs)
        }
        case '_' :: '_' :: cs if (cxt.headOption == Some("b_")) => {
          cxt = cxt.tail
          (MPlain(res.reverse.mkString), cs)
        }
        case '*' :: cs if cxt.headOption == Some("i*") => {
          cxt = cxt.tail
          (MPlain(res.reverse.mkString), cs)
        }
        case '_' :: cs if cxt.headOption == Some("i_") => {
          cxt = cxt.tail
          (MPlain(res.reverse.mkString), cs)
        }
        case ']' :: cs if cxt.headOption == Some("[") => {
          cxt = cxt.tail
          (MPlain(res.reverse.mkString), cs)
        }
        case '~' :: '~' :: '~' :: cs => if (!res.isEmpty) {
          (MPlain(res.reverse.mkString), x)
        } else {
          cxt = "o~" :: cxt
          val (xs, rest) = parseManyToken(cs, List())
          (MStyle(MSOutdated, xs), rest)
        }
        case '~' :: '~' :: cs => if (!res.isEmpty) {
          (MPlain(res.reverse.mkString), x)
        } else {
          cxt = "s~" :: cxt
          val (xs, rest) = parseManyToken(cs, List())
          (MStyle(MSStrike, xs), rest)
        }
        case '*' :: '*' :: cs => if (!res.isEmpty) {
          (MPlain(res.reverse.mkString), x)
        } else {
          cxt = "b*" :: cxt
          val (xs, rest) = parseManyToken(cs, List())
          (MStyle(MSBold, xs), rest)
        }
        case '_' :: '_' :: cs => if (!res.isEmpty) {
          (MPlain(res.reverse.mkString), x)
        } else {
          cxt = "b_" :: cxt
          val (xs, rest) = parseManyToken(cs, List())
          (MStyle(MSBold, xs), rest)
        }
        case '_' :: cs => if (!res.isEmpty) {
          (MPlain(res.reverse.mkString), x)
        } else {
          cxt = "i_" :: cxt
          val (xs, rest) = parseManyToken(cs, List())
          (MStyle(MSItal, xs), rest)
        }
        case '*' :: cs => if (!res.isEmpty) {
          (MPlain(res.reverse.mkString), x)
        } else {
          cxt = "i*" :: cxt
          val (xs, rest) = parseManyToken(cs, List())
          (MStyle(MSItal, xs), rest)
        }
        case '[' :: cs => if (!res.isEmpty) {
          (MPlain(res.reverse.mkString), x)
        } else {
          cxt = "[" :: cxt
          val (xs, rest) = parseManyToken(cs, List())
          val (link, title, restrest) = parseLink(rest)
          (MLink(false, xs, link.replaceAll("&nbsp;"," ").trim, title.map(_.replaceAll("&nbsp;"," ").trim)), restrest)
        }
        case '!' :: '[' :: cs => if (!res.isEmpty) {
          (MPlain(res.reverse.mkString), x)
        } else {
          cxt = "[" :: cxt
          val (xs, rest) = parseManyToken(cs, List())
          val (link, title, restrest) = parseLink(rest)
          (MLink(true, xs, link.replaceAll("&nbsp;"," ").trim, title.map(_.replaceAll("&nbsp;"," ").trim)), restrest)
        }
        case '#' :: cs => if (!res.isEmpty) {
          (MPlain(res.reverse.mkString), x)
        } else {
          val (color, rest) = cs.splitAt(6)
          if (color.map(x => (x >= '0' && x <= '9') || (x >= 'A' && x <= 'F')).reduce(_ && _))
            (MColor(color.mkString), rest)
          else parseToken(cs, '#' :: res)
        }
        case Nil => (MPlain(res.reverse.mkString), List())
        case c :: cs => parseToken(cs, c :: res)
      }
    }


    // like span, but consider escape characters
    def span2(cs: List[Char])(p:Char => Boolean)(isEscape: Char => Boolean) : (List[Char], List[Char]) = cs match {
      case List() => (List(), List())
      case List(x) =>  if (p(x)) (List(x), List()) else (List(), List(x))
      case x :: y :: zs => if( isEscape(x) ) span2(zs)(p)(isEscape).leftMap(y :: _)
                           else (if (p(x))   span2(y::zs)(p)(isEscape).leftMap(x :: _)
                                 else        (List(), x :: y :: zs))
    }

    def parseLink(x: List[Char]): (String, Option[String], List[Char]) = {
      val ret = x match {
        case '(' :: cs => {
          var (l, r) = span2(cs)(y => y != ')' && y != '"')(x => x == '\\')
          r match {
            case '"' :: css => {
              val (l1, r1) = span2(css)(y => y != '"')(x => x == '\\')
              r1 match {
                case '"' :: csss => (l.mkString, Some(l1.mkString), span2(csss)(y => y != ')')(x => x == '\\')._2.drop(1))
                case _ => ("", None, x)
              }
            }
            case ')' :: css => (l.mkString, None, css)
            case _ => ("", None, x)
          }
        }
        case _ => ("", None, x)
      }
      ret
    }

    @tailrec
    def parseManyToken(x: List[Char], res: List[MSyntax]): (List[MSyntax], List[Char]) = {
      var cxtlen = cxt.length
      if (x.isEmpty) (res.reverse, List())
      else parseToken(x, List()) match {
        case (ms, xs) => {
          if (cxt.length < cxtlen)
            ((ms :: res).reverse, xs)
          else
            parseManyToken(xs, ms :: res)
        }
      }
    }
    parseManyToken(inp.toList, List())._1
  }

  def truncateMarkdown(s: String, len: Int): String = {
    def goSyntax(ms: MSyntax, n: Int): (MSyntax, Int) = ms match {
      case MStyle(s, inner) => goList(inner, n) match {
        case (newInner, newN) => (MStyle(s, newInner), newN)
      }
      case MLink(b, inner, dest, title) => goList(inner, n) match {
        case (newInner, newN) => (MLink(b, newInner, dest, title), newN)
      }
      case MColor(c) => (MColor(c), n - 1)
      case MPlain(s) => if (s.length > n) (MPlain(s.take(n - 3) + "..."), 0) else (MPlain(s), n - s.length)
    }

    def go(nxt: MSyntax, sofar: (List[MSyntax], Int)): (List[MSyntax], Int) = {
      if (sofar._2 <= 0) sofar
      else goSyntax(nxt, sofar._2) match {
        case (ms, n) => (ms :: sofar._1, n)
      }
    }
    def goList(l: List[MSyntax], n: Int): (List[MSyntax], Int) = l.foldRight((List(): List[MSyntax], len))(go)
    goList(parseMarkdown(s), len)._1.map(markdownToString).mkString
  }

  def markdownToString(m: MSyntax): String = m match {
    case MStyle(MSBold, i) => "__" + i.map(markdownToString).mkString + "__"
    case MStyle(MSItal, i) => "*" + i.map(markdownToString).mkString + "*"
    case MPlain(s) => escapeForMarkdown(s)
    case MLink(isimage, i, dest, title) =>
      (if (isimage) "![" else "[") +
        i.map(markdownToString).mkString +
        "](" + dest +
        title.map(t => " \"" + t + "\"").getOrElse("") + ")"
    case MColor(c) => "#" + c
  }

  // Strips any markdown and just renders the text as a string
  def markdownToPlainString(m: MSyntax): String = m match {
    case MStyle(_, i) =>  i.map(markdownToPlainString).mkString 
    case MPlain(s) => s
    case MLink(isimage, i, dest, title) =>
      
        i.map(markdownToPlainString).mkString
    case MColor(c) => "#" + c
  }
  def mapMarkdown(f: String => String)(markdown: MSyntax): MSyntax = markdown match {
    case MStyle(s, i) => MStyle(s, i.map(mapMarkdown(f)))
    case MPlain(s) => MPlain(f(s))
    case MLink(isimage, i, dest, title) => MLink(isimage, i.map(mapMarkdown(f)), dest, title)
    case MColor(c) => MColor(c)
  }

  def markdownStringToHTML(s: String): String = markdownListToHTML(parseMarkdown(s))

  def markdownListToHTML(l: List[MSyntax]): String = l.map(markdownToHTML).mkString

  def markdownToHTML(markdown: MSyntax): String = {
    def wrapImgInner(s : String, inner : List[MSyntax]) = {
      val is = markdownListToHTML(inner)
      if(is.size > 0)
	("<div>"+s+"<br>"+is+"</div>")
      else s
    }
    markdown match {
      case MPlain(c) => c // todo escaping
      case MStyle(MSBold, inner) => "<b>" + markdownListToHTML(inner) + "</b>"
      case MStyle(MSItal, inner) => "<i>" + markdownListToHTML(inner) + "</i>"
      case MLink(isImage, inner, dest, Some(title)) =>
        if (isImage) wrapImgInner("<img src=\"" + dest + "\" alt=\"" + title + "\"/>", inner)
        else "<a href=\"" + dest + "\" title=\"" + title + "\">" + markdownListToHTML(inner) + "</a>"
      case MLink(isImage, inner, dest, None) =>
        if (isImage) wrapImgInner("<img src=\"" + dest + "\"/>",inner)
        else "<a href=\"" + dest + "\">" + markdownListToHTML(inner) + "</a>"
      case MColor(color) => "<span style='display:inline-block;height:10px;width:10px;background-color:#" + color + ";'>&nbsp;&nbsp;</span>"
    }
  }

  def escapeForMarkdown(s: String): String = {
    val charsToEscape = List("\\","*", "_", "(", ")", "[", "]","#")
    charsToEscape.foldLeft(s){ case (acc, old) => acc.replace(old, "\\" + old) }
  }

}
