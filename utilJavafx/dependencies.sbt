libraryDependencies += "org.scalaz" %% "scalaz-core" % "7.0.7"

libraryDependencies +=
  "log4j" % "log4j" % "1.2.15" excludeAll(
    ExclusionRule(organization = "com.sun.jdmk"),
    ExclusionRule(organization = "com.sun.jmx"),
    ExclusionRule(organization = "javax.jms"),
    ExclusionRule(organization = "javax.mail"),
    ExclusionRule(organization = "javax.activation")
  )

