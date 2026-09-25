package com.clarifi.reporting

import com.clarifi.reporting.ermine.lsp.{ Json, Preview }
import Preview.{ ConnectRequest, Profile }

import java.nio.file.Files

import org.scalacheck.{ Gen, Prop, Properties }
import Prop._

/** WP-13, THE SERVER HALF (DB programme stage 2a, tracker/db/SERVER.md §2 and
  * §5): the preview's connection profile, WITHOUT a database server.
  *
  *  - validation: every refusal `ermine/preview/connect` answers BEFORE ANY
  *    SOCKET (class `profile`, reason `connect-profile`), and that no refusal
  *    echoes the url, the host or the password;
  *  - the connect answer's `host`/`database`, parsed from the URL;
  *  - the §8.3 classifier over SQLState / vendor code (auth kept:false,
  *    locked/expired kept:true, driver, unreachable);
  *  - the answer shapes and their key order (wire contract);
  *  - the A10 scrub: the user as a token, never inside `ermine.preview.*`;
  *  - one bench over the real wire: a refused connect, a driver failure,
  *    disconnect -> the 503 `not-connected` with NO boot, and a held
  *    in-memory SQLite profile that renders.
  *
  * The live half (ErmineSales, DbFetchTopN, a wrong password) is
  * `TestPreviewDbLive`, env-gated and run by the `db` gate. */
object TestPreviewProfile extends Properties("Preview connection profile (WP-13 server half)") {

  import PreviewSupport._

  private val Secret = "s3cr3t-PW.x_9"
  private val Host   = "db.example.test"
  private val MsUrl  = "jdbc:sqlserver://127.0.0.1:1433;databaseName=ErmineSales;encrypt=true;trustServerCertificate=true"

  private def prof(fields: (String, Json)*): Json = Json.obj("profile" -> Json.obj(fields: _*))
  private def s(v: String): Json = Json.Str(v)

  private lazy val liteFile: java.nio.file.Path = {
    val f = Files.createTempFile("ermine-wp13-", ".sqlite")
    f.toFile.deleteOnExit()
    f
  }

  /** Each case must be refused, and the refusal must not echo a secret. */
  private def refused(name: String, params: Json): Prop = {
    val r = ConnectRequest.parse(params)
    val msg = r.left.toOption.getOrElse("")
    (r.isLeft :| (name + ": accepted " + r)) &&
      (!msg.contains(Secret) :| (name + ": echoed the password: " + msg)) &&
      (!msg.contains(Host) :| (name + ": echoed the host: " + msg)) &&
      (!msg.contains("jdbc:sqlserver://") :| (name + ": echoed the url: " + msg))
  }

  property("validation: malformed, mismatched, relative or missing profiles are refused before any socket, echoing no secret") = {
    val cases: List[(String, Json)] = List(
      "no profile"          -> Json.obj("password" -> s(Secret)),
      "profile not object"  -> Json.obj("profile" -> s("sales")),
      "no id"               -> prof("dialect" -> s("mssql"), "url" -> s(MsUrl)),
      "no dialect"          -> prof("id" -> s("x"), "url" -> s(MsUrl)),
      "no url"              -> prof("id" -> s("x"), "dialect" -> s("mssql")),
      "empty id"            -> prof("id" -> s(" "), "dialect" -> s("mssql"), "url" -> s(MsUrl)),
      "user not a string"   -> prof("id" -> s("x"), "dialect" -> s("mssql"), "url" -> s(MsUrl), "user" -> Json.num(3)),
      "unknown dialect"     -> prof("id" -> s("x"), "dialect" -> s("oracle"), "url" -> s("jdbc:oracle:thin:@" + Host)),
      "noTransactions on sqlite" -> prof("id" -> s("x"), "dialect" -> s("sqlite"), "url" -> s("jdbc:sqlite::memory:"),
                                         "scanner" -> s("noTransactions")),
      "not a JDBC url"      -> prof("id" -> s("x"), "dialect" -> s("mssql"), "url" -> s("sqlserver://" + Host)),
      "mssql over sqlite url" -> prof("id" -> s("x"), "dialect" -> s("mssql"), "url" -> s("jdbc:sqlite:" + liteFile)),
      "sqlite over mssql url" -> prof("id" -> s("x"), "dialect" -> s("sqlite"),
                                      "url" -> s("jdbc:sqlserver://" + Host + ":1433;databaseName=D")),
      "userinfo in url"     -> prof("id" -> s("x"), "dialect" -> s("postgres"),
                                    "url" -> s("jdbc:postgresql://bob:" + Secret + "@" + Host + "/d")),
      "relative sqlite"     -> prof("id" -> s("x"), "dialect" -> s("sqlite"), "url" -> s("jdbc:sqlite:data/out/sales.sqlite")),
      "relative file: sqlite" -> prof("id" -> s("x"), "dialect" -> s("sqlite"), "url" -> s("jdbc:sqlite:file:sales.sqlite?mode=ro")),
      "missing sqlite file" -> prof("id" -> s("x"), "dialect" -> s("sqlite"), "url" -> s("jdbc:sqlite:/nonexistent-wp13/dir/x.sqlite")),
      "password, no user"   -> Json.obj("profile" -> Json.obj("id" -> s("x"), "dialect" -> s("sqlite"),
                                                            "url" -> s("jdbc:sqlite::memory:")),
                                        "password" -> s(Secret)))
    cases.map { case (n, j) => refused(n, j) }.reduce(_ && _)
  }

  /** A9's keys, in a random mix of cases, anywhere after `;`. */
  private val credKeys = List("password", "pwd", "user", "userName", "integratedSecurity", "authentication")
  private val genCredUrl: Gen[String] = for {
    k    <- Gen.oneOf(credKeys)
    ups  <- Gen.listOfN(k.length, Gen.oneOf(true, false))
    pad  <- Gen.oneOf("", " ")
    head <- Gen.oneOf(";databaseName=D", ";encrypt=true;databaseName=D", "")
  } yield "jdbc:sqlserver://" + Host + ":1433" + head + ";" + pad +
          k.zip(ups).map { case (c, u) => if (u) c.toUpper else c.toLower }.mkString + pad + "=" + Secret

  property("validation: a url carrying credentials (A9, any case) is refused and not echoed") =
    forAll(genCredUrl) { url =>
      refused("credentials", prof("id" -> s("x"), "dialect" -> s("mssql"), "url" -> s(url), "user" -> s("ermine")))
    }

  property("validation: well-formed profiles pass (mssql with user+password, sqlite :memory:, an absolute sqlite file)") = {
    val ok = List(
      Json.obj("profile" -> Json.obj("id" -> s("sales-mssql"), "dialect" -> s("mssql"), "url" -> s(MsUrl),
                                     "user" -> s("ermine")), "password" -> s(Secret)),
      Json.obj("profile" -> Json.obj("id" -> s("nt"), "dialect" -> s("SqlServer"), "url" -> s(MsUrl),
                                     "user" -> s("ermine"), "scanner" -> s("noTransactions"))),
      prof("id" -> s("mem"), "dialect" -> s("sqlite"), "url" -> s("jdbc:sqlite::memory:")),
      prof("id" -> s("twin"), "dialect" -> s("sqlite"), "url" -> s("jdbc:sqlite:" + liteFile)),
      prof("id" -> s("twin2"), "dialect" -> s("sqlite"), "url" -> s("jdbc:sqlite:file:" + liteFile + "?mode=ro")))
    ok.map { j =>
      val r = ConnectRequest.parse(j)
      (r.isRight :| ("refused " + Json.print(j).replace(Secret, "<pw>") + ": " + r.left.toOption)) &&
        (!r.toString.contains(Secret) :| "the request's toString printed the password")
    }.reduce(_ && _)
  }

  property("host and database come from the URL alone") = {
    def hd(d: String, u: String) = Preview.hostAndDatabase(d, u)
    (hd("mssql", MsUrl) ?= ("127.0.0.1", "ErmineSales")) &&
    (hd("mssql", "jdbc:sqlserver://srv\\inst;database=Sales2") ?= ("srv", "Sales2")) &&
    (hd("mssql", "jdbc:sqlserver://;serverName=h9;databaseName=Q") ?= ("h9", "Q")) &&
    (hd("postgres", "jdbc:postgresql://pg.local:5432/reports?ssl=true") ?= ("pg.local", "reports")) &&
    (hd("sqlite", "jdbc:sqlite:/abs/dir/ErmineSales.sqlite") ?= ("local", "ErmineSales.sqlite")) &&
    (hd("sqlite", "jdbc:sqlite::memory:") ?= ("local", ":memory:"))
  }

  property("classifier (§8.3): SQLState/vendor code decide auth kept:false, locked/expired kept:true, driver, unreachable") = {
    import java.sql.SQLException
    val login   = new SQLException("Login failed for user 'ermine'.", "S0001", 18456)
    val state   = new SQLException("bad credentials", "28000", 0)
    val expired = new SQLException("password expired", "S0001", 18487)
    val locked  = new SQLException("account locked", "S0001", 18486)
    val noDrv   = new SQLException("No suitable driver found for jdbc:sqlserver://" + Host, "08001")
    val refused = new SQLException("The TCP/IP connection to the host " + Host + " has failed", "08S01", 0)
    val tls     = new SQLException("The driver could not establish a secure connection", "08S01", 0,
                                   new javax.net.ssl.SSLHandshakeException("PKIX path building failed"))
    val wrapped = new RuntimeException("wrapper", login)
    (Preview.classify(login)   ?= ("auth", false)) &&
    (Preview.classify(state)   ?= ("auth", false)) &&
    (Preview.classify(wrapped) ?= ("auth", false)) &&
    (Preview.classify(expired) ?= ("auth", true)) &&
    (Preview.classify(locked)  ?= ("auth", true)) &&
    (Preview.classify(new ClassNotFoundException("no.such.Driver")) ?= ("driver", true)) &&
    (Preview.classify(new ExceptionInInitializerError("static init")) ?= ("driver", true)) &&
    (Preview.classify(noDrv)   ?= ("driver", true)) &&
    (Preview.classify(refused) ?= ("unreachable", true)) &&
    (Preview.classify(tls)     ?= ("unreachable", true)) &&
    (Preview.classify(new java.net.SocketTimeoutException("timed out")) ?= ("unreachable", true))
  }

  private def keys(j: Json): List[String] = j match { case Json.Obj(fs) => fs.map(_._1); case _ => Nil }

  property("answer shapes: connect ok / failure keys in wire order, reason = connect-<class>, no url in a message") = {
    val ok = Preview.connectOk("sales-mssql", "mssql", "127.0.0.1", "ErmineSales", "16.00.4295", 3)
    val shapes = List("auth", "driver", "unreachable", "profile").map { c =>
      val f = Preview.connectFailure(c, "No suitable driver found for " + MsUrl, kept = c != "auth")
      (keys(f) ?= List("ok", "class", "message", "kept", "reason")) &&
        ((f / "reason" flatMap (_.str)) ?= Some("connect-" + c)) &&
        ((f / "kept" flatMap (_.bool)) ?= Some(c != "auth")) &&
        (!(f / "message" flatMap (_.str)).exists(_.contains("jdbc:")) :| ("url in " + Json.print(f)))
    }
    (keys(ok) ?= List("ok", "id", "dialect", "host", "database", "server", "seq")) &&
      ((ok / "seq" flatMap (_.int)) ?= Some(3)) &&
      shapes.reduce(_ && _)
  }

  property("A10 scrub: url, host and user as tokens; ermine.preview.* and ermine/render untouched; documents untouched") = {
    val p = Profile("sales-mssql", "mssql", MsUrl, Some("ermine"), None, "default")
    val t = Preview.scrubTermsFor(p)
    def sc(x: String) = Preview.applyScrub(t, x)
    val answer = Json.obj("ok" -> Json.Bool(false), "message" -> s("Login failed for user 'ermine'. at 127.0.0.1:1433"),
                          "document" -> s("ermine rocks at 127.0.0.1"))
    val scrubbed = Preview.scrubAnswerMessages(t, answer)
    (sc("Login failed for user 'ermine'.") ?= "Login failed for user '<user>'.") &&
    (sc("connect to 127.0.0.1:1433 failed") ?= "connect to <host>:1433 failed") &&
    (sc("the url " + MsUrl + " is bad") ?= "the url <url> is bad") &&
    (sc("ermine.preview.timeoutSeconds and ermine/render") ?= "ermine.preview.timeoutSeconds and ermine/render") &&
    (sc("hermine and ermine2") ?= "hermine and ermine2") &&
    ((scrubbed / "message" flatMap (_.str)) ?= Some("Login failed for user '<user>'. at <host>:1433")) &&
    ((scrubbed / "document" flatMap (_.str)) ?= Some("ermine rocks at 127.0.0.1"))
  }

  property("login timeout: below the watchdog, 1..15 s, 15 s when the watchdog is off") =
    forAll(Gen.choose(0L, 3600L)) { secs =>
      val lt = Preview.loginTimeoutSeconds(secs * 1000L)
      (lt >= 1 && lt <= 15) :| ("login timeout " + lt) &&
        ((secs == 0L || secs < 2L || lt < secs) :| ("login " + lt + " s is not below the watchdog's " + secs + " s"))
    }

  // ------------------------------------------------------------------ the wire

  private def result(a: Option[Json]): Option[Json] = a flatMap (_ / "result")
  private def field(a: Option[Json], k: String): Option[Json] = result(a) flatMap (_ / k)

  property("wire: refused connect, driver failure, disconnect -> 503 not-connected with no boot, held in-memory SQLite renders") =
    secure {
      previewLock.synchronized { ErmineFixture.literalLock.synchronized {
        val b = new Bench(warm = false)
        try {
          val fixture = writeFixture("WpProfile", wpSimple("WpProfile", 7))
          // 1. refused before any socket, the password nowhere
          b.request(1, "ermine/preview/connect", Json.obj(
            "profile" -> Json.obj("id" -> s("bad"), "dialect" -> s("mssql"),
                                  "url" -> s("jdbc:sqlserver://" + Host + ";password=" + Secret), "user" -> s("ermine")),
            "password" -> s(Secret)))
          val a1 = b.answer(1, 60000L)
          // 2. a driver class that does not exist: class driver, kept
          b.request(2, "ermine/preview/connect", Json.obj(
            "profile" -> Json.obj("id" -> s("nodrv"), "dialect" -> s("sqlite"), "url" -> s("jdbc:sqlite::memory:"),
                                  "driver" -> s("no.such.Driver"))))
          val a2 = b.answer(2, 60000L)
          // 3. disconnect, then a render: 503 not-connected, and NO boot
          b.request(3, "ermine/preview/disconnect", Json.obj())
          val a3 = b.answer(3, 60000L)
          b.renderWith(4, fixture, "report", "1", 40, List(previewRoot))
          val a4 = b.answer(4, 60000L)
          val bootsWhileDown = b.boots
          // 4. a held in-memory SQLite profile, then the render boots on it
          b.request(5, "ermine/preview/connect", Json.obj(
            "profile" -> Json.obj("id" -> s("mem"), "dialect" -> s("sqlite"), "url" -> s("jdbc:sqlite::memory:"))))
          val a5 = b.answer(5, 60000L)
          b.renderWith(6, fixture, "report", "1", 41, List(previewRoot))
          val a6 = b.answer(6, 300000L)
          val log = b.sink.result()
          val leaked = log.exists(_.contains(Secret)) || b.remaining().exists(j => Json.print(j).contains(Secret))
          ((field(a1, "ok") flatMap (_.bool)) ?= Some(false)) &&
          ((field(a1, "class") flatMap (_.str)) ?= Some("profile")) &&
          ((field(a1, "reason") flatMap (_.str)) ?= Some("connect-profile")) &&
          ((field(a1, "kept") flatMap (_.bool)) ?= Some(true)) &&
          ((field(a2, "class") flatMap (_.str)) ?= Some("driver")) &&
          ((field(a2, "reason") flatMap (_.str)) ?= Some("connect-driver")) &&
          ((field(a3, "ok") flatMap (_.bool)) ?= Some(true)) &&
          ((field(a4, "status") flatMap (_.int)) ?= Some(503)) &&
          ((field(a4, "reason") flatMap (_.str)) ?= Some("not-connected")) &&
          ((field(a4, "message") flatMap (_.str)) ?= Some("not connected")) &&
          ((field(a4, "generation") flatMap (_.int)) ?= Some(40)) &&
          ((bootsWhileDown ?= 0) :| "a disconnected render booted a session") &&
          ((field(a5, "ok") flatMap (_.bool)) ?= Some(true)) &&
          ((field(a5, "dialect") flatMap (_.str)) ?= Some("sqlite")) &&
          ((field(a5, "host") flatMap (_.str)) ?= Some("local")) &&
          ((field(a5, "database") flatMap (_.str)) ?= Some(":memory:")) &&
          ((field(a5, "seq") flatMap (_.int)) ?= Some(1)) &&
          (((field(a6, "ok") flatMap (_.bool)) ?= Some(true)) :| ("held render " + a6.map(Json.print))) &&
          (!leaked :| "the password reached the log or the wire") &&
          (log.exists(_.contains("preview: connected mem (sqlite)")) :| "no connected log line")
        } finally { b.stop(); () }
      } }
    }
}
