package com.clarifi.reporting
package writers

import scalaz._
import Scalaz._

case class StyleGrid[+A](styleGrid:  List[(Option[String], List[(Option[String], A)])]) {
	def map[B](f: A => B): StyleGrid[B] = 
		StyleGrid(styleGrid.map(x => (x._1, x._2.map(y => (y._1, f(y._2))))))

	def append[B>:A](s2: StyleGrid[B]): StyleGrid[B] = 
		StyleGrid(styleGrid ++ s2.styleGrid)

	def applyStyle[B](applyRowStyle: (Option[String], List[B]) => List[B])(applyCellStyle: (Option[String], A) => B): List[List[B]] = 
		styleGrid.map(x => applyRowStyle(x._1, x._2.map(y => applyCellStyle(y._1, y._2))))
}

object StyleGrid {
	implicit def styleGridTraverse: Traverse[StyleGrid] = new Traverse[StyleGrid] {
		override def traverseImpl[G[_], A, B](fa: StyleGrid[A])(f: (A) => G[B])(implicit applicativeG: Applicative[G]) = {
			fa.styleGrid.traverse(_.traverse(_.traverse(_.traverse(f)))).map(StyleGrid(_))
		}
	}
}