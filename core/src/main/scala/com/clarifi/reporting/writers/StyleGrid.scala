package com.clarifi.reporting
package writers

private[writers] case class StyleList[+A](styleList: List[(Option[String], A)]) {
	def map[B](f: A => B): StyleList[B] = 
		StyleList(styleList.map(x => (x._1, f(x._2))))

	def append[B>:A](l2: StyleList[B]): StyleList[B] = 
		StyleList(styleList ++ l2.styleList)

	def applyStyle[B](f: (Option[String], A) => B) : List[B] = 
		styleList.map(x => f(x._1, x._2))
}

case class StyleGrid[+A](styleGrid: StyleList[StyleList[A]]) {
	def map[B](f: A => B): StyleGrid[B] = 
		StyleGrid(styleGrid.map(_.map(f)))

	def append[B>:A](s2: StyleGrid[B]): StyleGrid[B] = 
		StyleGrid(styleGrid.append(s2.styleGrid))

	def applyStyle[B](applyRowStyle: (Option[String], List[B]) => List[B])(applyCellStyle: (Option[String], A) => B): List[List[B]] = 
		styleGrid.map(_.applyStyle(applyCellStyle)).applyStyle(applyRowStyle)
}
