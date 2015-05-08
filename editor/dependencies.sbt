libraryDependencies ++= Seq (
  "org.scala-lang"  % "scala-swing"              % "2.9.2",
  "org.webjars"     % "jquery-ui"                % "1.8.21",
  // all of this is for html writer testing
  "net.databinder" %% "unfiltered-filter"        % "0.6.8",
  "net.databinder" %% "unfiltered-jetty"         % "0.6.8"
    exclude("org.eclipse.jetty.orbit", "javax.servlet"),
  "net.databinder" %% "unfiltered-spec"          % "0.6.8"
    exclude("org.eclipse.jetty.orbit", "javax.servlet"),
  "net.databinder" %% "unfiltered-netty-uploads" % "0.6.8",
  "org.clapper"    %% "avsl"                     % "0.4",
  "net.debasishg"  %% "sjson"                    % "0.19"
)

