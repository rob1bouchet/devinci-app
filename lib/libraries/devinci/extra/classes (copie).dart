import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:devinci/libraries/devinci/extra/functions.dart';
import 'package:devinci/extra/globals.dart' as globals;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

class User {
  //constructor
  User(String username, String password) {
    this.username = username;
    this.password = password;
  }

  //values
  String username;
  String password;

  bool error = false;
  int code = 200;

  Map<String, String> tokens = {
    "SimpleSAML": "",
    "alv": "",
    "uids": "",
    "SimpleSAMLAuthToken": "",
  };

  void reset() async {
    this.tokens["SimpleSAML"] = "";
    this.tokens["alv"] = "";
    this.tokens["SimpleSAMLAuthToken"] = "";
    await globals.storage.deleteAll();
  }

  Map<String, String> data = {
    "badge": "",
    "client": "",
    "idAdmin": "",
    "ine": "",
    "edtUrl": "",
    "name": "",
  };

  Map<String, dynamic> absences = {
    "nT": 0,
    "s1": 0,
    "s2": 0,
    "seances": 0,
    "liste": [],
    "done": false
  };

  Map<String, List> notes = {
    "s1": [],
    "s2": [],
  };

  bool notesFetched = false;

  var promotion = {};

  Map<String, String> presence = {
    "type": "",
    "title": "",
    "horaires": "",
  };

  Map<String, dynamic> documents = {
    "certificat": {
      "annee": "",
      "fr_url": "",
      "en_url": "",
    },
    "imaginr": {
      "annee": "",
      "url": "",
    },
    "calendrier": {
      "annee": "",
      "url": "",
    },
    "bulletins": []
  };

  Future<void> init() async {
    //init sembast db
    Directory directory;
    if (Platform.isAndroid) {
      directory = await getExternalStorageDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }
    final String path = directory.path;
    // File path to a file in the current directory
    String dbPath = path + '/data/db.db';
    DatabaseFactory dbFactory = databaseFactoryIo;

// We use the database factory to open the database
    globals.db = await dbFactory.openDatabase(dbPath);
    Map<String, dynamic> notes = await globals.store
        .record('notes')
        .get(globals.db) as Map<String, dynamic>;
    if (notes == null) {
      notes = {
        "s1": [],
        "s2": [],
      };
      await globals.store.record('notes').put(globals.db, notes);
    }
    //this.notes["s1"] = notes["s1"];
    //this.notes["s2"] = notes["s2"];
    //ici on va faire qqchose de peu sympa et pas très efficient mais on y est obligé parce que les données de la db sont sous la forme immutable, en copiant ces données directement dans notre classe il nous est alors impossible de mettre a jour les notes.
    for (int y = 0; y < 2; y++) {
      this.notes["s${y + 1}"] = [];
      int i = 0;
      notes["s${y + 1}"].forEach((sem) {
        Map<String, dynamic> elem = {
          "module": sem["module"],
          "moy": sem["moy"],
          "nf": sem["nf"],
          "moyP": sem["moyP"],
          "matieres": []
        };

        this.notes["s${y + 1}"].add(elem);
        int j = 0;
        sem["matieres"].forEach((mat) {
          elem = {
            "matiere": mat["matiere"],
            "moy": mat["moy"],
            "moyP": mat["moyP"],
            "notes": [],
            "c": true
          };
          this.notes["s${y + 1}"][i]["matieres"].add(elem);
          int w = 0;
          mat["notes"].forEach((note) {
            elem = {
              "nom": note["nom"],
              "note": note["note"],
              "noteP": note["noteP"],
              "date": note["date"]
            };
            this.notes["s${y + 1}"][i]["matieres"][j]["notes"].add(elem);
            w++;
          });
          j++;
        });
        i++;
      });
    }
    print("notes");
    print(this.notes);
    //retrieve tokens from secure storage (if they exist)
    this.tokens["SimpleSAML"] = await globals.storage.read(key: "SimpleSAML") ??
        ""; //try to get token SimpleSAML from secure storage, if secure storage send back null (because the token does't exist yet) '??' means : if null, so if the token doesn't exist replace null by an empty string.
    this.tokens["alv"] = await globals.storage.read(key: "alv") ?? "";
    this.tokens["uids"] = await globals.storage.read(key: "uids") ?? "";
    this.tokens["SimpleSAMLAuthToken"] =
        await globals.storage.read(key: "SimpleSAMLAuthToken") ?? "";

    //retrieve data from secure storage
    globals.crashConsent = await globals.storage.read(key: "crashConsent");
    this.data["badge"] = await globals.storage.read(key: "badge") ?? "";
    this.data["client"] = await globals.storage.read(key: "client") ?? "";
    this.data["idAdmin"] = await globals.storage.read(key: "idAdmin") ?? "";
    this.data["ine"] = await globals.storage.read(key: "ine") ?? "";
    this.data["edtUrl"] = await globals.storage.read(key: "edtUrl") ?? "";
    this.data["name"] = await globals.storage.read(key: "name") ?? "";
    try {
      l("test tokens");
      await this
          .testTokens(); //test if tokens exist and if so, test if they are still valid
    } catch (exception) {
      l("test tokens exception : $exception");

      //testTokens throw an exception if tokens don't exist or if they aren't valid
      //as the tokens don't exist yet or aren't valid, we shall retrieve them from devinci's server
      try {
        await this.getTokens();
      } catch (exception) {
        //getTokens throw an exception if an error occurs during the retrieving or if credentials are wrong
        if (this.code == 500) {
          //the exception was thrown by a dart process, which meens that credentials may be good, but the function had trouble to access the server.
          //TODO implement a retry process.

        } else if (this.code == 401) {
          await globals.storage
              .deleteAll(); //remove all sensitive data from the phone if the user can't connect
          //the exception was thrown because credentials are wrong
          Crashlytics.instance.recordError(
            "classes.dart | getToken | wrong credentials => '${this.username}':'${this.password}'",
            StackTrace.fromString(""),
          );

          throw Exception(
              "wrong credentials : $exception"); //throw an exception to indicate to the parent process that credentials are wrong and may need to be changed
        } else {
          throw Exception(exception); //we don't know what happened here
        }
      }
    }
    //if we manage to arrive here it means that we have valid tokens and that credentials are good
    //TODO implement "remember me" function
    await globals.storage.write(
        key: "username",
        value: this
            .username); //save credentials in secure storage if user specified "remember me"
    await globals.storage.write(key: "password", value: this.password);
    this.password =
        null; //if tokens are still valid we'll never need the password again in this session, so it is useless to keep it in the object and risk it to be leaked or displayed
    if (globals.user.data["edtUrl"] == "") {
      //edtUrl being the last information we retrieve from the getData() function, if it doesn't exist it means that the getData() function didn't work or was never run and must be run at least once.
      try {
        await globals.user.getData();
      } catch (exception) {
        //print(exception);
      }
    }
    //print("done init");
    return;
  }

  Future<void> getTokens() async {
    HttpClient client = new HttpClient();

    if (this.username != "" && this.password != "") {
      HttpClientRequest req = await client.getUrl(
        Uri.parse('https://www.leonard-de-vinci.net/'),
      );
      HttpClientResponse res = await req.close();

      l('statusCode : ${res.statusCode}');
      l('headers : ${res.headers}');
      l('STEP 1 : HEADERS - SET-COOKIE : ${res.headers.value("set-cookie")}');
      RegExp regExp = new RegExp(r'(.*?)=(.*?)($|;|,(?! ))');
      this.tokens["alv"] = regExp
          .firstMatch(
            res.headers.value("set-cookie"),
          )
          .group(2);
      l('ALV : "${this.tokens['alv']}"');
      if (res.statusCode == 200) {
        req = await client.postUrl(
            Uri.parse('https://www.leonard-de-vinci.net/ajax.inc.php'));
        req.headers.set(
            'Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
        req.headers.set('Referer', 'https://www.leonard-de-vinci.net/');
        req.headers.set('Cookie', 'alv=${this.tokens["alv"]}');
        req.write(
            "act=ident_analyse&login=" + Uri.encodeComponent(this.username));
        l("[STEP 2] REQ HEADERS : ${req.headers}");
        res = await req.close();
        l('[STEP 2] statusCode : ${res.statusCode}');
        l('[STEP 2] RES headers : ${res.headers}');
        String body = await res.transform(utf8.decoder).join();
        l('[STEP 2] BODY : $body');
        if (body.indexOf("location") > -1) {
          l('username correct');

          req = await client.getUrl(
            Uri.parse(
                'https://www.leonard-de-vinci.net/login.sso.php?username=' +
                    Uri.encodeComponent(this.username)),
          );
          req.followRedirects = false;
          req.headers.set('Referer', 'https://www.leonard-de-vinci.net/');
          req.headers.set('Cookie', 'alv=${this.tokens["alv"]}');
          l("[STEP 3] REQ HEADERS : ${req.headers}");
          res = await req.close();
          l('[STEP 3] statusCode : ${res.statusCode}');
          l('[STEP 3] RES headers : ${res.headers}');
          this.tokens["SimpleSAML"] = regExp
              .firstMatch(
                res.headers.value("set-cookie"),
              )
              .group(2);
          l('SimpleSAML : "${this.tokens['SimpleSAML']}"');

          String redUrl = res.headers.value("location");

          req = await client.getUrl(
            Uri.parse(redUrl),
          );
          res = await req.close();
          l('[STEP 4] statusCode : ${res.statusCode}');
          l('[STEP 4] RES headers : ${res.headers}');
          body = await res.transform(utf8.decoder).join();
          //l('[STEP 4] BODY : $body');
          regExp = new RegExp(r'action="\/adfs(.*?)"');
          String url =
              "https://adfs.devinci.fr/adfs" + regExp.firstMatch(body).group(1);
          l('[STEP 4] url : $url');

          req = await client.postUrl(
            Uri.parse(url),
          );
          req.headers.set('Content-Type', 'application/x-www-form-urlencoded');
          req.write("UserName=" +
              Uri.encodeComponent(this.username) +
              "&Password=" +
              Uri.encodeComponent(this.password) +
              "&AuthMethod=FormsAuthentication");
          l("[STEP 5] REQ HEADERS : ${req.headers}");
          res = await req.close();
          l('[STEP 5] statusCode : ${res.statusCode}');
          l('[STEP 5] RES headers : ${res.headers}');

          if (res.headers.value("set-cookie") != null &&
              res.statusCode == 302) {
            l('connected');
            regExp = new RegExp(r'(.*?)=(.*?)($|;|,(?! ))');
            String MSISAuth = regExp
                .firstMatch(
                  res.headers.value("set-cookie"),
                )
                .group(2);
            redUrl = res.headers.value("location");

            req = await client.getUrl(
              Uri.parse(redUrl),
            );
            req.headers.set("Cookie", "MSISAuth=" + MSISAuth);
            l("[STEP 6] REQ HEADERS : ${req.headers}");
            res = await req.close();
            l('[STEP 6] statusCode : ${res.statusCode}');
            l('[STEP 6] RES headers : ${res.headers}');
            body = await res.transform(utf8.decoder).join();
            regExp = new RegExp(r'value="(.*?)"');
            String value = regExp.firstMatch(body).group(1);

            //l('value : $value');
            req = await client.postUrl(
              Uri.parse(
                  "https://www.leonard-de-vinci.net/include/SAML/module.php/saml/sp/saml2-acs.php/devinci-sp"),
            );
            req.headers
                .set("Content-Type", "application/x-www-form-urlencoded");
            req.headers.set("Cookie",
                "alv=${this.tokens["alv"]}; SimpleSAML=${this.tokens["SimpleSAML"]}");
            req.followRedirects = false;
            String b = "SAMLResponse=" +
                Uri.encodeComponent(value) +
                "&RelayState=https://www.leonard-de-vinci.net/login.sso.php";
            req.write(b);
            l("[STEP 7] REQ HEADERS : ${req.headers}");
            res = await req.close();
            l('[STEP 7] statusCode : ${res.statusCode}');
            l('[STEP 7] RES headers : ${res.headers}');
            body = await res.transform(utf8.decoder).join();
            l("set-cookie : ${res.headers['set-cookie']}");
            if (res.statusCode == 303) {
              redUrl = res.headers.value("location");
              regExp = new RegExp(r'(.*?)=(.*?)($|;|,(?! ))');
              this.tokens["SimpleSAMLAuthToken"] = regExp
                  .firstMatch(
                    res.headers['set-cookie'][1],
                  )
                  .group(2);
              l('SimpleSAMLAuthToken : "${this.tokens["SimpleSAMLAuthToken"]}"');

              req = await client.getUrl(
                Uri.parse(redUrl),
              );
              req.followRedirects = false;
              req.headers.set(
                  "Cookie",
                  "alv=" +
                      this.tokens["alv"] +
                      "; SimpleSAML=" +
                      this.tokens["SimpleSAML"] +
                      "; SimpleSAMLAuthToken=" +
                      this.tokens["SimpleSAMLAuthToken"]);
              l("[STEP 8] REQ HEADERS : ${req.headers}");
              res = await req.close();
              l('[STEP 8] statusCode : ${res.statusCode}');
              l('[STEP 8] RES headers : ${res.headers}');
              //body = await res.transform(utf8.decoder).join();
              this.tokens["uids"] = regExp
                  .firstMatch(
                    res.headers['set-cookie'][2],
                  )
                  .group(2);
              l('uids : "${this.tokens["uids"]}"');
              await globals.storage.write(
                key: "SimpleSAML",
                value: this.tokens["SimpleSAML"],
              );
              await globals.storage.write(
                key: "alv",
                value: this.tokens["alv"],
              );
              await globals.storage.write(
                key: "SimpleSAMLAuthToken",
                value: this.tokens["SimpleSAMLAuthToken"],
              );
              await globals.storage.write(
                key: "uids",
                value: this.tokens["uids"],
              );
              this.error = false;
              this.code = 200;
            } else {
              this.error = true;
              this.code = res.statusCode;
              throw Exception("unhandled error");
            }
          } else {
            this.error = true;
            this.code = 401;
            throw Exception("wrong credentials");
          }
        } else {
          l('username incorrect');
          this.error = true;
          this.code = 401;
          throw Exception("wrong credentials");
        }
      } else {
        this.error = true;
        this.code = res.statusCode;
        throw Exception("Error while retrieving alv token");
      }
    } else {
      this.error = true;
      this.code = 400;
      throw Exception("missing parameters");
    }
    return;
  }

  Future<void> testTokens() async {
    HttpClient client = new HttpClient();

    //check if all tokens are still valid:
    if (this.tokens["SimpleSAML"] != "" &&
        this.tokens["alv"] != "" &&
        this.tokens["uids"] != "" &&
        this.tokens["SimpleSAMLAuthToken"] != "" &&
        this.error == false) {
      this.error = true;
      this.code = 400;

      HttpClientRequest request = await client.getUrl(
        Uri.parse('https://www.leonard-de-vinci.net/'),
      );
      request.followRedirects = false;
      // request.cookies.addAll([
      //   new Cookie('alv', this.tokens["alv"]),
      //   new Cookie('SimpleSAML', this.tokens["SimpleSAML"]),
      //   new Cookie('uids', this.tokens["uids"]),
      //   new Cookie('SimpleSAMLAuthToken', this.tokens["SimpleSAMLAuthToken"]),
      // ]);
      request.headers.set("Cookie",
          "alv=${this.tokens["alv"]}; SimpleSAML=${this.tokens["SimpleSAML"]}; SimpleSAMLAuthToken=${this.tokens["SimpleSAMLAuthToken"]}; uids=${this.tokens["uids"]}");
      //request.headers.add("set",
      //"Mozilla/5.0 (iPhone; CPU iPhone OS 13_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/11.2 Mobile/15E148 Safari/604.1");
      //print(request.headers);
      HttpClientResponse response = await request.close();

      l('statusCode : ${response.statusCode}');
      l('headers : ${response.headers}');
      String body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        //print(body);
        if (body.indexOf("('#password').hide();") > -1) {
          l("error");
          throw Exception("wrong tokens");
        } else {
          this.error = false;
          this.code = 200;
        }
      } else {
        throw Exception("wrong tokens -> statuscode : ${response.statusCode}");
      }
    } else {
      this.error = true;
      this.code = 400;
      throw Exception("missing tokens or user as error");
    }
    return;
  }

  Future<void> getData() async {
    HttpClient client = new HttpClient();
    if (this.tokens["SimpleSAML"] != "" &&
        this.tokens["alv"] != "" &&
        this.tokens["uids"] != "" &&
        this.tokens["SimpleSAMLAuthToken"] != "" &&
        this.error == false) {
      this.error = true;
      this.code = 400;

      HttpClientRequest request = await client.getUrl(
        Uri.parse('https://www.leonard-de-vinci.net/'),
      );
      request.followRedirects = false;
      request.cookies.addAll([
        new Cookie('alv', this.tokens["alv"]),
        new Cookie('SimpleSAML', this.tokens["SimpleSAML"]),
        new Cookie('uids', this.tokens["uids"]),
        new Cookie('SimpleSAMLAuthToken', this.tokens["SimpleSAMLAuthToken"]),
      ]);
      HttpClientResponse response = await request.close();

      l('statusCode : ${response.statusCode}');
      l('headers : ${response.headers}');
      String body = await response.transform(utf8.decoder).join();
      //print("get Data");
      if (response.statusCode == 200) {
        //print(body);
        var doc = parse(body);
        //print(doc.outerHtml);
        List<Element> ns = doc.querySelectorAll("#main > div > .row-fluid");
        Element n = ns[ns.length - 1].querySelector(
            "div.social-box.social-blue.social-bordered > header > h4");
        //print('n : "${n.innerHtml}"');
        RegExp regExp = new RegExp(r": (.*?)\t");
        this.data["name"] = regExp.firstMatch(n.text).group(1);
        l("name : '${this.data["name"]}'");

        List<Element> ds = ns[ns.length - 1].querySelectorAll(
            "div.social-box.social-blue.social-bordered > div > div");
        //print(ds);
        //print("ds 0 : " + ds[0].innerHtml);
        //print("ds 1 : " + ds[1].innerHtml);
        //print("ds 2 : " + ds[2].innerHtml);
        String d;
        if (ds[1].innerHtml.indexOf("Identifiant") > -1) {
          //print("ds1 choosen");
          //print(ds[1]
          //    .querySelector("div"));
          d = ds[1]
              .querySelector("div > div > div.span4 > div > div > address")
              .text;
          l("d : $d");
        } else {
          d = ds[2]
              .querySelector("div > div > div.span4 > div > div > address")
              .text;
          l("d : $d");
        }
        this.data["badge"] =
            new RegExp(r"badge : (.*?)\n").firstMatch(d).group(1);
        this.data["client"] =
            new RegExp(r"client (.*?)\n").firstMatch(d).group(1);
        this.data["idAdmin"] =
            new RegExp(r"Administratif (.*?)\n").firstMatch(d).group(1);
        this.data["ine"] =
            new RegExp(r"INE/BEA : (.*?)\n").firstMatch(d).group(1);
        l("data : ${this.data["badge"]}|${this.data["client"]}|${this.data["idAdmin"]}|${this.data["ine"]}");

        request = await client
            .getUrl(Uri.parse("https://www.leonard-de-vinci.net/?my=edt"));
        request.followRedirects = false;
        request.cookies.addAll([
          new Cookie('alv', this.tokens["alv"]),
          new Cookie('SimpleSAML', this.tokens["SimpleSAML"]),
          new Cookie('uids', this.tokens["uids"]),
          new Cookie('SimpleSAMLAuthToken', this.tokens["SimpleSAMLAuthToken"]),
        ]);
        response = await request.close();

        l('statusCode : ${response.statusCode}');
        l('headers : ${response.headers}');
        body = await response.transform(utf8.decoder).join();
        if (response.statusCode == 200) {
          this.data["edtUrl"] = "https://ical.devinci.me/" +
              new RegExp(r'ical.devinci.me\/(.*?)"').firstMatch(body).group(1);
          l("ical url : ${this.data["edtUrl"]}");
          await globals.storage.write(
            key: "badge",
            value: this.data["badge"],
          );
          await globals.storage.write(
            key: "client",
            value: this.data["client"],
          );
          await globals.storage.write(
            key: "idAdmin",
            value: this.data["idAdmin"],
          );
          await globals.storage.write(
            key: "ine",
            value: this.data["ine"],
          );
          await globals.storage.write(
            key: "edtUrl",
            value: this.data["edtUrl"],
          );
          await globals.storage.write(
            key: "name",
            value: this.data["name"],
          );
        } else {
          this.error = true;
          this.code = response.statusCode;
          throw Exception("unhandled exception");
        }
      } else {
        this.error = true;
        this.code = response.statusCode;
        throw Exception("unhandled exception");
      }
    } else {
      this.error = true;
      this.code = 400;
      throw Exception("missing parameters");
    }
    return;
  }

  Future<void> getAbsences() async {
    HttpClient client = new HttpClient();
    if (this.tokens["SimpleSAML"] != "" &&
        this.tokens["alv"] != "" &&
        this.tokens["uids"] != "" &&
        this.tokens["SimpleSAMLAuthToken"] != "") {
      HttpClientRequest req = await client.getUrl(
        Uri.parse("https://www.leonard-de-vinci.net/?my=abs"),
        //Uri.parse("https://araulin.tech/devinci/absences.html"),
      );
      req.followRedirects = false;
      req.cookies.addAll([
        new Cookie('alv', this.tokens["alv"]),
        new Cookie('SimpleSAML', this.tokens["SimpleSAML"]),
        new Cookie('uids', this.tokens["uids"]),
        new Cookie('SimpleSAMLAuthToken', this.tokens["SimpleSAMLAuthToken"]),
      ]);
      HttpClientResponse res = await req.close();
      if (res.statusCode == 200) {
        String body = await res.transform(utf8.decoder).join();
        var doc = parse(body);
        //print(doc.outerHtml);
        List<Element> spans = doc.querySelectorAll(".tab-pane > header > span");
        Element nTB =
            doc.querySelector(".tab-pane > header > span.label.label-warning");
        print(nTB);
        String nTM =
            new RegExp(r': (.*?)"').firstMatch(nTB.text + '"').group(1);
        this.absences["nT"] = int.parse(nTM);

        String s1M =
            new RegExp(r': (.*?)"').firstMatch(spans[0].text + '"').group(1);
        this.absences["s1"] = int.parse(s1M);

        Element s2B =
            doc.querySelector(".tab-pane > header > span.label.label-success");
        String s2M =
            new RegExp(r': (.*?)"').firstMatch(s2B.text + '"').group(1);
        this.absences["s2"] = int.parse(s2M);

        String seanceM = new RegExp(r'"(.*?) séance')
            .firstMatch('"' + spans[3].text)
            .group(1);
        this.absences["seances"] = int.parse(seanceM);
        List<Element> trs =
            doc.querySelectorAll(".tab-pane .active > table > tbody > tr");
        trs.forEach((tr) {
          Map<String, String> elem = {
            "cours": "",
            "type": "",
            "jour": "",
            "creneau": "",
            "duree": "",
            "modalite": ""
          };

          List<Element> tds = tr.querySelectorAll("td");
          elem["cours"] = tds[1]
              .text
              .replaceAll(tds[1].querySelector("span").text, "")
              .replaceAllMapped(RegExp(r'\s\s+'), (match) => "");
          elem["type"] =
              tds[2].text.replaceAllMapped(RegExp(r'\s\s+'), (match) => "");
          elem["jour"] =
              tds[3].text.replaceAllMapped(RegExp(r'\s\s+'), (match) => "");
          elem["creneau"] =
              tds[4].text.replaceAllMapped(RegExp(r'\s\s+'), (match) => "");
          elem["duree"] =
              tds[5].text.replaceAllMapped(RegExp(r'\s\s+'), (match) => "");
          elem["modalite"] =
              tds[6].text.replaceAllMapped(RegExp(r'\s\s+'), (match) => "");
          this.absences["liste"].add(elem);
        });
        this.absences["done"] = true;
        // JsonEncoder encoder = new JsonEncoder.withIndent('  ');
        //   String prettyprint = encoder.convert(this.absences);
        //   print(prettyprint);
      } else {
        this.error = true;
        this.code = res.statusCode;
        throw Exception("unhandled exception");
      }
    } else {
      this.error = true;
      this.code = 400;

      throw Exception("missing parameters => " +
          this.tokens["SimpleSAML"] +
          " | " +
          this.tokens["alv"] +
          " | " +
          this.tokens["SimpleSAMLAuthToken"] +
          " | " +
          this.tokens["uids"] +
          " | " +
          this.error.toString());
    }
    return;
  }

  Future<void> getNotes() async {
    int changed = 0;
    int added = 0;
    HttpClient client = new HttpClient();
    if (this.tokens["SimpleSAML"] != "" &&
        this.tokens["alv"] != "" &&
        this.tokens["uids"] != "" &&
        this.tokens["SimpleSAMLAuthToken"] != "") {
      int timestamp = DateTime.now().millisecondsSinceEpoch;

      //this.notes["s1"] = [];
      //this.notes["s2"] = [];
      Map<String, dynamic> notes = {"s1": [], "s2": []};
      this.notes["s1"].forEach((element) {
        notes["s1"].add(element);
      });
      this.notes["s2"].forEach((element) {
        notes["s2"].add(element);
      });
      HttpClientRequest req = await client.getUrl(
        //Uri.parse('https://www.leonard-de-vinci.net/?my=notes'),
        Uri.parse('http://araulin.tech/devinci/raulin_notes.html'),
      );
      req.followRedirects = false;
      req.cookies.addAll([
        new Cookie('alv', this.tokens["alv"]),
        new Cookie('SimpleSAML', this.tokens["SimpleSAML"]),
        new Cookie('uids', this.tokens["uids"]),
        new Cookie('SimpleSAMLAuthToken', this.tokens["SimpleSAMLAuthToken"]),
      ]);
      HttpClientResponse res = await req.close();
      l("NOTES - STATUS CODE : ${res.statusCode}");
      if (res.statusCode == 200) {
        String body = await res.transform(utf8.decoder).join();
        var doc = parse(body);

        List<Element> divs = doc.querySelectorAll("#main > div > div");
        for (int y = 0; y < 2; y++) {
          int i = 0;
          List<Element> ols1 = divs[5].querySelectorAll(
              "div > div > div.social-box.social-bordered > div > div > div.dd > ol");
          List<Element> ols = ols1[y].querySelector("li").children;
          for (int yy = 1; yy < ols.length; yy++) {
            Element ol = ols[yy];
            Map<String, dynamic> elem = {
              "module": "",
              "moy": 0.0,
              "nf": 0.0,
              "moyP": 0.0,
              "matieres": []
            };
            Element li = ol.querySelector("li");
            Element ddhandle = ol.querySelector("div");
            List<String> texts = ddhandle.text.split("\n");
            JsonEncoder encoder = new JsonEncoder.withIndent('  ');
            String prettyprint = encoder.convert(texts);
            print(prettyprint);
            elem["module"] =
                texts[2].replaceAllMapped(RegExp(r'\s\s+'), (match) => "");

            elem["moy"] = null;
            elem["nf"] = null;
            elem["moyP"] = null;
            if (texts[5]
                    .indexOf("Vous devez compléter toutes les évaluations") <
                0) {
              elem["moy"] = double.parse(texts[6]
                  .replaceAllMapped(RegExp(r'\s\s+'), (match) => "")
                  .split("/")[0]);
              elem["nf"] = double.parse(
                  RegExp(r': (.*?)"').firstMatch(texts[7] + '"').group(1));
              elem["moyP"] = double.parse(
                  RegExp(r': (.*?)"').firstMatch(texts[9] + '"').group(1));
            }
            print(
                "notes > i:$i | ['${"s${y + 1}"}'].length:${this.notes["s${y + 1}"].length}");
            if (this.notes["s${y + 1}"].length > i) {
              if (this.notes["s${y + 1}"][i]["module"] != elem["module"]) {
                this.notes["s${y + 1}"][i]["module"] = elem["module"];
              }
              if (this.notes["s${y + 1}"][i]["moy"] != elem["moy"]) {
                this.notes["s${y + 1}"][i]["moy"] = elem["moy"];
              }
              if (this.notes["s${y + 1}"][i]["nf"] != elem["nf"]) {
                this.notes["s${y + 1}"][i]["nf"] = elem["nf"];
              }
              if (this.notes["s${y + 1}"][i]["moyP"] != elem["moyP"]) {
                this.notes["s${y + 1}"][i]["moyP"] = elem["moyP"];
              }
            } else {
              this.notes["s${y + 1}"].add(elem);
            }
            Element ddlist = li.querySelector("ol");
            int j = 0;
            ddlist.children.forEach((lii) {
              ddhandle = lii.querySelector("div");
              texts = ddhandle.text.split("\n");
              //String prettyprint = encoder.convert(texts);
              // print(prettyprint);
              elem = {
                "matiere": "",
                "moy": 0.0,
                "moyP": 0.0,
                "notes": [],
                "c": true
              };

              elem["matiere"] =
                  texts[2].replaceAllMapped(RegExp(r'\s\s+'), (match) => "");
              elem["moy"] = null;
              elem["moyP"] = null;
              if (texts[3].indexOf("Evaluer") < 0) {
                elem["moy"] = double.parse(texts[6]
                    .replaceAllMapped(RegExp(r'\s\s+'), (match) => "")
                    .split("/")[0]);
                //print(elem["moy"]);

                if (texts[9].indexOf("Rattrapage") < 0) {
                  try {
                    elem["moyP"] = double.parse(RegExp(r': (.*?)"')
                        .firstMatch(texts[10] + '"')
                        .group(1));
                  } catch (e) {
                    elem["moyP"] = null;
                  }
                } else {
                  double noteR = double.parse(
                      RegExp(r': (.*?)"').firstMatch(texts[9] + '"').group(1));
                  if (noteR > elem["moy"]) {
                    if (noteR > 10) {
                      elem["moy"] = 10.0;
                    } else {
                      elem["moy"] = noteR;
                    }
                  }
                  var e = {
                    "nom": "MESIMF120419-CC-1 Rattrapage",
                    "note": noteR,
                    "noteP": null,
                    "date": timestamp
                  };
                  if (this
                          .notes["s${y + 1}"][i]["matieres"][j]["notes"]
                          .length >
                      0) {
                    if (this.notes["s${y + 1}"][i]["matieres"][j]["notes"][0]
                                ["nom"] !=
                            e["nom"] ||
                        this.notes["s${y + 1}"][i]["matieres"][j]["notes"][0]
                                ["note"] !=
                            e["note"]) {
                      this.notes["s${y + 1}"][i]["matieres"][j]["notes"][0] = e;
                    }
                  } else {
                    elem["notes"].add(e);
                  }

                  elem["moyP"] = double.parse(
                      RegExp(r': (.*?)"').firstMatch(texts[11] + '"').group(1));
                }
              }
              print(
                  "notes > j:$j | ['matières'].length:${this.notes["s${y + 1}"][i]["matieres"].length}");
              if (this.notes["s${y + 1}"][i]["matieres"].length > j) {
                if (this.notes["s${y + 1}"][i]["matieres"][j]["matiere"] !=
                    elem["matiere"]) {
                  this.notes["s${y + 1}"][i]["matieres"][j]["matiere"] =
                      elem["matiere"];
                }
                if (this.notes["s${y + 1}"][i]["matieres"][j]["moy"] !=
                    elem["moy"]) {
                  this.notes["s${y + 1}"][i]["matieres"][j]["moy"] =
                      elem["moy"];
                }
                if (this.notes["s${y + 1}"][i]["matieres"][j]["moyP"] !=
                    elem["moyP"]) {
                  this.notes["s${y + 1}"][i]["matieres"][j]["moyP"] =
                      elem["moyP"];
                }
              } else {
                this.notes["s${y + 1}"][i]["matieres"].add(elem);
              }
              int w = 0;
              ddlist = lii.querySelector("ol");
              ddlist.children.forEach((liii) {
                ddhandle = liii.querySelector("div");
                texts = ddhandle.text.split("\n");
                elem = {
                  "nom": "",
                  "note": 0.0,
                  "noteP": 0.0,
                  "date": timestamp
                };
                elem["nom"] =
                    texts[2].replaceAllMapped(RegExp(r'\s\s+'), (match) => "");
                if (texts.length < 7) {
                  elem["note"] = null;
                  elem["noteP"] = null;
                } else {
                  elem["note"] = double.parse(texts[6]
                      .replaceAllMapped(RegExp(r'\s\s+'), (match) => "")
                      .split("/")[0]);
                  elem["noteP"] = null;
                  try {
                    elem["noteP"] = double.parse(RegExp(r': (.*?)"')
                        .firstMatch(texts[10] + '"')
                        .group(1));
                  } catch (e) {}
                }
                print(
                    "notes > w:$w | ['notes'].length:${this.notes["s${y + 1}"][i]["matieres"][j]["notes"].length}");
                if (this.notes["s${y + 1}"][i]["matieres"][j]["notes"].length >
                    w) {
                  if (this.notes["s${y + 1}"][i]["matieres"][j]["notes"][w]
                              ["nom"] !=
                          elem["nom"] ||
                      this.notes["s${y + 1}"][i]["matieres"][j]["notes"][w]
                              ["note"] !=
                          elem["note"]) {
                    changed++;
                    this.notes["s${y + 1}"][i]["matieres"][j]["notes"][w] =
                        elem;
                  }
                } else {
                  added++;
                  this.notes["s${y + 1}"][i]["matieres"][j]["notes"].add(elem);
                }

                w++;
              });
              j++;
            });
            i++;
          }
        }
      } else {
        this.error = true;
        this.code = res.statusCode;
        throw Exception("unhandled exception");
      }
    } else {
      this.error = true;
      this.code = 400;

      throw Exception("missing parameters => " +
          this.tokens["SimpleSAML"] +
          " | " +
          this.tokens["alv"] +
          " | " +
          this.tokens["SimpleSAMLAuthToken"] +
          " | " +
          this.tokens["uids"] +
          " | " +
          this.error.toString());
    }
    await globals.store.record('notes').put(globals.db, this.notes);
    this.notesFetched = true;
    print("db updated | $changed notes modifiées et $added notes ajoutées");
    return;
  }

  Future<void> getDocuments() async {
    HttpClient client = new HttpClient();
    if (this.tokens["SimpleSAML"] != "" &&
        this.tokens["alv"] != "" &&
        this.tokens["uids"] != "" &&
        this.tokens["SimpleSAMLAuthToken"] != "") {
      HttpClientRequest req = await client.getUrl(
        Uri.parse("https://www.leonard-de-vinci.net/?my=docs"),
      );
      req.followRedirects = false;
      req.cookies.addAll([
        new Cookie('alv', this.tokens["alv"]),
        new Cookie('SimpleSAML', this.tokens["SimpleSAML"]),
        new Cookie('uids', this.tokens["uids"]),
        new Cookie('SimpleSAMLAuthToken', this.tokens["SimpleSAMLAuthToken"]),
      ]);
      HttpClientResponse res = await req.close();
      if (res.statusCode == 200) {
        String body = await res.transform(utf8.decoder).join();
        var doc = parse(body);
        //Element cert = doc.querySelector("#main > div > div:nth-child(5) > div:nth-child(2) > div > table > tbody > tr > td:nth-child(2)");
        int certIndex = 1;
        int imaginrIndex = 1;
        for (int i = 1;
            i <
                doc
                    .querySelectorAll(".social-box.social-bordered.span6")[1]
                    .querySelectorAll("tr")
                    .length;
            i++) {
          print(doc
              .querySelectorAll(".social-box.social-bordered.span6")[1]
              .querySelectorAll("tr")[i]
              .querySelectorAll("td")[1]
              .text);
          if (doc
                  .querySelectorAll(".social-box.social-bordered.span6")[1]
                  .querySelectorAll("tr")[i]
                  .querySelectorAll("td")[0]
                  .text
                  .indexOf("scolarité") >
              -1) {
            certIndex = i;
          } else if (doc
                  .querySelectorAll(".social-box.social-bordered.span6")[1]
                  .querySelectorAll("tr")[i]
                  .querySelectorAll("td")[0]
                  .text
                  .indexOf("ImaginR") >
              -1) {
            imaginrIndex = i;
          }
        }
        List<Element> certElements = doc
            .querySelectorAll(".social-box.social-bordered.span6")[1]
            .querySelectorAll("tr")[certIndex]
            .querySelectorAll("td");

        this.documents["certificat"]["annee"] = certElements[1].text;
        this.documents["certificat"]["fr_url"] =
            "https://www.leonard-de-vinci.net" +
                certElements[2].querySelectorAll("a")[0].attributes["href"];
        this.documents["certificat"]["en_url"] =
            "https://www.leonard-de-vinci.net" +
                certElements[2].querySelectorAll("a")[1].attributes["href"];

        print(this.documents["certificat"]["annee"]);
        print(this.documents["certificat"]["fr_url"]);
        print(this.documents["certificat"]["en_url"]);

        List<Element> imaginrElements = doc
            .querySelectorAll(".social-box.social-bordered.span6")[1]
            .querySelectorAll("tr")[imaginrIndex]
            .querySelectorAll("td");

        this.documents["imaginr"]["annee"] = imaginrElements[1].text;
        this.documents["imaginr"]["url"] = "https://www.leonard-de-vinci.net" +
            imaginrElements[2].querySelectorAll("a")[0].attributes["href"];

        int calendrierIndex = 4;
        for (int i = 0;
            i <
                doc
                    .querySelectorAll(".social-box.social-bordered.span6")[0]
                    .querySelectorAll("a")
                    .length;
            i++) {
          if (doc
                      .querySelectorAll(".social-box.social-bordered.span6")[0]
                      .querySelectorAll("a")[i]
                      .text
                      .indexOf("CALENDRIER ACADEMIQUE") >
                  -1 &&
              doc
                      .querySelectorAll(".social-box.social-bordered.span6")[0]
                      .querySelectorAll("a")[i]
                      .text
                      .indexOf("APPRENTISSAGE") <
                  0) {
            calendrierIndex = i;
          }
        }

        this.documents["calendrier"]["url"] =
            "https://www.leonard-de-vinci.net" +
                doc
                    .querySelectorAll(".social-box.social-bordered.span6")[0]
                    .querySelectorAll("a")[calendrierIndex]
                    .attributes["href"];
        this.documents["calendrier"]["annee"] = RegExp(r"\d{4}-\d{4}")
            .firstMatch(doc
                .querySelectorAll(".social-box.social-bordered.span6")[0]
                .querySelectorAll("a")[calendrierIndex]
                .text)
            .group(0);

        print(
            "calendrier : ${this.documents["calendrier"]["annee"]}|${this.documents["calendrier"]["url"]}");

        //documents liés aux notes :
        req = await client.getUrl(
          Uri.parse("https://www.leonard-de-vinci.net/?my=notes"),
        );
        req.followRedirects = false;
        req.cookies.addAll([
          new Cookie('alv', this.tokens["alv"]),
          new Cookie('SimpleSAML', this.tokens["SimpleSAML"]),
          new Cookie('uids', this.tokens["uids"]),
          new Cookie('SimpleSAMLAuthToken', this.tokens["SimpleSAMLAuthToken"]),
        ]);
        res = await req.close();
        if (res.statusCode == 200) {
          body = await res.transform(utf8.decoder).join();
          doc = parse(body);
          List<Element> filesA = doc
              .querySelectorAll(
                  "div.body")[doc.querySelectorAll("div.body").length - 2]
              .querySelectorAll("a:not(.label)");
          print(filesA);
          for (int i = 0; i < filesA.length; i += 2) {
            this.documents["bulletins"].add({
              "name": filesA[i].text.substring(1, filesA[i].text.length - 1),
              "fr_url": "https://www.leonard-de-vinci.net" +
                  filesA[i].attributes["href"],
              "en_url": "https://www.leonard-de-vinci.net" +
                  filesA[i + 1].attributes["href"],
              "sub": RegExp(r'\s\s+(.*?)\s\s+')
                  .firstMatch(doc
                      .querySelectorAll("div.body")[
                          doc.querySelectorAll("div.body").length - 2]
                      .querySelector("header")
                      .text
                      .split("\n")
                      .last)
                  .group(1)
            });
          }
          print(this.documents["bulletins"]);
        }
      }
    }
  }
}

class Cours {
  Cours(this.eventName, this.from, this.to, this.background, this.isAllDay);

  String eventName;
  DateTime from;
  DateTime to;
  material.Color background;
  bool isAllDay;
}

class ReceivedNotification {
  final int id;
  final String title;
  final String body;
  final String payload;

  ReceivedNotification({
    @required this.id,
    @required this.title,
    @required this.body,
    @required this.payload,
  });
}
