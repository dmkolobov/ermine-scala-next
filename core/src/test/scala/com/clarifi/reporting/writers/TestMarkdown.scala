package com.clarifi.reporting.writers

import scalaz.NonEmptyList
import org.scalacheck.{Arbitrary, Gen, Prop, Properties}
import Arbitrary.arbitrary
import Prop.{AnyOperators, forAll, propBoolean, secure}

object TestMarkdown extends Properties("Markdown") {
  import Markdown._

  property("parse anything") = forAll((s:String) =>  s.length() > 0 ==> {
    parseMarkdown(s).nonEmpty
  })

  property("parse empty") = secure { parseMarkdown("") == List() }

  test(  "_test_",   MStyle(MSItal, List(MPlain("test"))))
  test(  "*test*",   MStyle(MSItal, List(MPlain("test"))))
  test( "__test__",  MStyle(MSBold, List(MPlain("test"))))
  test( "**test**",  MStyle(MSBold, List(MPlain("test"))))
  test("_**test**_", MStyle(MSItal, List(MStyle(MSBold, List(MPlain("test"))))))
  test("__*test*__", MStyle(MSBold, List(MStyle(MSItal, List(MPlain("test"))))))


  List("MStyle(MSItal,List(MStyle(MSBold,List(MPlain(test)))))")
  List("MStyle(MSItal,List(MStyle(MSBold,List(MPlain(test))), MPlain()))")

  def test(markdown:String, expected:MSyntax) = property(markdown) = secure {
    println(parseMarkdown(markdown))
    cleanAll(parseMarkdown(markdown)) ?= cleanAll(List(expected))
  }
  
  def cleanAll(ms:List[MSyntax]) : List[MSyntax] = {
    def clean(m:MSyntax): MSyntax = m match {
      case MStyle(s, inner) => MStyle(s, cleanAll(inner))
      case MLink(isImage, inner, dest, title) =>
        MLink(isImage, cleanAll(inner), dest, title)
      case x => x
    }
    ms.foldLeft(List[MSyntax]()){
      case (acc, MPlain("")) => acc
      case (acc, x) => acc ++ List(clean(x))
    }
  }
}
