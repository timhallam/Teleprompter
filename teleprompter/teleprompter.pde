// Make sure JS is being hosted (run the batch file) before running this code, otherwise it'll never do anything.
// It will start Chrome automatically however, and close it if you use "Command - Close".

import processing.video.*;
import websockets.*;

String scriptpath = "D:/script.txt"; // change this for a different script location. suggest an SD card or USB drive
WebsocketServer socket;
StringList speech; // this is the last words received from STT
int speechsize = 6; // size of the max word-match
int accuracy = 4; // min words matched for location to update
StringList script; // this is the as-written script line-wrapped for rendering
PGraphics pg;
ArrayList<Word> scriptwords; // this is a sanitised script used for tracking speech location in script
int twidth;
int textsize = 80; // font size
int lineheight = int(float(textsize) * 1.1);
int wordpointer = 0;
int readahead = 10; // limit on how far forward the word-match will look ahead before giving up
int border;
boolean commandmode = false;
int commandattempt;
boolean mirrormode = true;
boolean scriptmode = true;
boolean frameratemode = false;
int displaylines;
float offset = 0;
Capture cam;

void setup()
{
  //size(1920, 1080); // uncomment if not fullscreen
  fullScreen();
  //surface.setAlwaysOnTop(true); // this was causing bugs
  frameRate(30); //
  twidth = int(width * 0.8); // modify this for the proportionate width of text within screen width
  displaylines = height / (lineheight * 2);
  socket = new WebsocketServer(this, 58008, "/stt");
  openBrowser();
  speech = new StringList();
  loadScript();
  border = (width - twidth) / 2;
  pg = createGraphics(width, height);
  pg.beginDraw();
  pg.textAlign(LEFT, TOP);
  pg.textSize(textsize);
  pg.endDraw();
  cam = new Capture(this, 1920, 1080, "pipeline:autovideosrc");
  if (mirrormode) cam.start();
}

void draw()
{
  background(0);
  if (mirrormode)
  {
    if (cam.available()) cam.read();
    image(cam, 0, 0);
    if (!scriptmode)
    {
      stroke(255, 0, 0);
      for (int n = 1; n < 3; n ++)
      {
        int x = (width * n) / 3;
        line(x, 0, x, height);
        int y = (height * n) / 3;
        line(0, y, width, y);
      }
    }
  }
  
  pg.beginDraw();
  pg.scale(-1, 1); // mirrors some screen elements (comment for non-reflective display eg testing on normal monitor)
  pg.translate(-width, 0); // shifts screen origin (only use if mirrored above)
  pg.background(0, 0);
  if (scriptmode)
  {
    if (mirrormode)
    {
      noStroke();
      fill(0, 127);
      rect(0, 0, width, height);
    }
    stroke(255, 200, 0);
    line(0, height / 2, width, height / 2);
    noStroke();
    pg.noStroke();
    pg.fill(255);
    int targetoffset = scriptwords.get(wordpointer).offset;
    float distance = targetoffset - offset;
    float travel = distance / 20;
    offset += travel;
    float yref = (height / 2) - offset;
    for (int n = 0; n < script.size(); n ++)
    {
      float liney = (n * lineheight) + yref;
      if (liney < -lineheight) continue; // skip text we've already scrolled past
      if (liney > height) break; // stop when we're past the bottom of the screen
      pg.text(script.get(n), border, liney);
    }
  }
  if (frameratemode)
  {
    pg.fill(255, 0, 0);
    pg.text("" + int(frameRate), 0, 0);
  }
  pg.endDraw();
  image(pg, 0, 0);
  if (commandmode)
  {
    fill(255, 0, 0);
    rect(width - 100, 50, 50, 50);
  }
}

void webSocketServerEvent(String msg)
{
  if (msg.length() == 0) return;
  addSpeech(clean(msg));
  updateLocation();
}

void updateLocation()
{
  // scans scriptwords for speech matches and updates the current location of speech within the script
  // assume current locat can never be backwards of last known location
  for (int wp = wordpointer + 1; wp < min(wordpointer + readahead, scriptwords.size()); wp ++)
  {
    float matched = 0;
    for (int w = wp; w > wp - speechsize && w >= 0; w --)
    {
      // try for matches in any order
      String word = scriptwords.get(w).word;
      if (speech.hasValue(word)) matched += 1.0;
    }
    
    if (matched >= accuracy)
    {
      wordpointer = wp;
      break;
    }
  }
}

String clean(String in)
{
  // removes punctuation etc
  String out = "";
  for (int n = 0; n < in.length(); n ++)
  {
    char c = in.charAt(n);
    if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z')) out += c;
  }
  return out;
}

void addSpeech(String word)
{
  if (word.length() == 0) return; // ignore keep-alive messages
  // look for wakeword and direct accordingly
  if (commandmode)
  {
    checkCommand(word);
    return;
  }
  
  if (speech.size() > 0 && word.startsWith(speech.get(speech.size() - 1)))
  {
    // It's common for intermediate STT results to include the first part of a longer word.
    // If the previous word was only a part of this word (eg "fill" followed by "filler")
    // then overwrite the partial word with the full one
    // - could be a problem for match accuracy, eg "to toast" will assume "to" didn't actually happen
    speech.remove(speech.size() - 1);
    print("#");
  }
  if (word.equals("command"))
  {
    println("COMMAND:>");
    commandmode = true;
    commandattempt = 0;
    return;
  }
  
  speech.append(word);
  while (speech.size() > speechsize) speech.remove(0); // keep the speech buffer to a set size
  println("\"" + word + "\"");
}

void checkCommand(String word)
{
  println(">" + word + "<");
  if (word.equals("mirror"))
  {
    mirrormode = !mirrormode;
    if (!mirrormode) cam.stop();
    else cam.start();
  }
  else if (word.equals("switch"))
  {
    frameratemode = false;
    if (mirrormode)
    {
      scriptmode = true;
      mirrormode = false;
      cam.stop();
    }
    else
    {
      scriptmode = false;
      mirrormode = true;
      cam.start();
    }
  }
  else if (word.equals("restart"))
  {
    wordpointer = 0;
    speech.clear();
  }
  else if (word.equals("script")) scriptmode = !scriptmode;
  else if (word.equals("frame")) frameratemode = !frameratemode;
  else if (word.equals("up"))
  {
    if (wordpointer > 0) wordpointer --;
    while (wordpointer > 0 && !scriptwords.get(wordpointer).paragraph) wordpointer --;
    speech.clear();
  }
  else if (word.equals("down"))
  {
    if (wordpointer < scriptwords.size() - 1) wordpointer ++;
    while (wordpointer < scriptwords.size() - 1 && !scriptwords.get(wordpointer).paragraph) wordpointer ++;
    speech.clear();
  }
  else if (word.equals("load"))
  {
    wordpointer = 0;
    speech.clear();
    loadScript();
    scriptmode = true;
  }
  else if (word.equals("close"))
  {
    closeBrowser();
    exit();
  }
  else
  {
    commandattempt ++;
    if (commandattempt == 1) return;
  }
  commandmode = false;
}

void loadScript()
{
  textSize(textsize);
  script = new StringList();
  String[] tempscript = loadStrings(scriptpath);
  for (int n = 0; n < tempscript.length; n ++)
  {
    if (tempscript[n].length() == 0) continue;
    if (n > 0) addLines("");
    addLines(">" + tempscript[n]);
  }
  
  // script is now full - make the words only list
  scriptwords = new ArrayList<Word>();
  for (int lineno = 0; lineno < script.size(); lineno ++)
  {
    String[] words = split(script.get(lineno), ' ');
    for (int wordno = 0; wordno < words.length; wordno ++)
    {
      if (words[wordno].length() == 0) continue;
      boolean newpara = words[wordno].charAt(0) == '>';
      if (newpara) script.set(lineno, script.get(lineno).substring(1)); // remove '>' marker
      String word = clean(words[wordno].toLowerCase());
      scriptwords.add(new Word(word, (lineheight * lineno) + ((wordno * lineheight) / words.length), newpara));
    }
  }
}

void addLines(String in)
{
  // add blank lines without further messing
  if (in.length() == 0)
  {
    script.append("");
    return;
  }
  // remove leading spaces
  if (in.charAt(0) == ' ')
  {
    addLines(in.substring(1));
    return;
  }
  // replace leading tabs with filler (because tabs don't render)
  String subtab = "";
  while (in.charAt(0) == '\t')
  {
    subtab += "- ";
    in = in.substring(1);
  }
  if (subtab.length() > 0) in = subtab + in;
  // wrap line to length
  String spill = "";
  while (textWidth(in) > twidth)
  {
    // move char by char to spill until length is achieved
    spill = in.charAt(in.length() - 1) + spill;
    in = in.substring(0, in.length() - 1);
  }
  // midword split - top up spill back to last space
  if (spill.length() > 0)
  {
    int space = in.lastIndexOf(' ');
    if (space > 0)
    {
      spill = in.substring(space) + spill;
      in = in.substring(0, space);
    }
  }
  script.append(in);
  if (spill.length() > 0) addLines(spill); // recursively handle everything that spilled over
}

void openBrowser()
{
  delay(1000);
  try
  {
    // open chrome at the correct local web page for the javascript code to run
    Runtime.getRuntime().exec(new String[] {"cmd.exe", "/c", "start chrome 127.0.0.1:8000"});
  }
  catch (Exception e)
  {
    println("Couldn't open the Chrome window for some reason");
    println(e);
  }
}

void closeBrowser()
{
  try
  {
    Runtime.getRuntime().exec(new String[] {"cmd.exe", "/c", "taskkill /F /IM chrome.exe /T"});
  }
  catch (Exception e)
  {
    println("Couldn't close the Chrome window for some reason");
    println(e);
  }
  
}
