; Title:   A simple AutoHotkey GUI application for creating short links using the Short.cm API.
; Author:  Callum Watkins
; Licence: MIT
; Usage:   Replace the API key variable below with your own key, include this file in
;          your own script and call ShortenURLGUI() to open the GUI. Select the domain,
;          long URL, etc. and click OK. The short URL will be copied to your clipboard.
; Supports the following properties: Domain, long URL, short URL slug, title, password.

SHORT_CM_API_KEY := "YOUR_API_KEY_HERE"

; Show a GUI with options for generating a short URL using the Short.cm API
ShortenURLGUI()
{
  global
  ; Load the domains the first time only
  if (!shortDomains) {
    shortDomains := GetDomains(SHORT_CM_API_KEY)
    
    if (shortDomains = 1) { ; 
      shortDomains =
      Return
    }

    if (shortDomains.MaxIndex() = 0) {
      MsgBox, 16, No domains, There are no domains associated with your account.
      shortDomains =
      Return
    }
  }

  ; Concatenate the domains with pipes for the DropDownList
  local domainString := ""
  for index, domain in shortDomains
    domainString := domainString domain "|"
  domainString := domainString "|" ; Extra pipe on the end to make the last domain the default

  ; Get the first line of the clipboard
  local clipboardNewLinePos := InStr(Clipboard,"`r")
  if (clipboardNewLinePos = 0)
    longUrl := Clipboard
  else
    longUrl := SubStr(Clipboard, 1, clipboardNewLinePos - 1)

  ; Build the GUI
  Gui, URLShortener:New
  
  Gui, Font, s16 bold, Tahoma
  Gui, Add, Text, , Short.cm URL Shortener

  Gui, Add, Text, w460 Y+20 0x10

  Gui, Font, s13 normal, Verdana
  Gui, Add, Text, Y+-10, Domain
  Gui, Font, s11
  Gui, Add, DropDownList, W200 Y+2 vDomain, %domainString%

  Gui, Font, s13
  Gui, Add, Text, Y+15, Long URL
  Gui, Font, s11
  Gui, Add, Edit, R1 W460 Y+2 vLongUrl, %longUrl%

  Gui, Font, s13
  Gui, Add, Text, Y+15, Short URL Slug (leave empty for random)
  Gui, Font, s11
  Gui, Add, Edit, R1 W200 Y+2 vSlug

  Gui, Font, s13
  Gui, Add, Text, Y+15, Link Title
  Gui, Font, s11
  Gui, Add, Edit, R1 W460 Y+2 vTitle

  Gui, Font, s13
  Gui, Add, Text, Y+15, Password
  Gui, Font, s11
  Gui, Add, Edit, R1 W200 Y+2 Password vPassword

  Gui, Add, Text, w460 Y+20 0x10

  Gui, Add, Button, W100 H30 X+-210 Y+0 Default gURLShortenButtonOK, OK
  Gui, Add, Button, W100 H30 X+10 gURLShortenButtonCancel, Cancel

  Gui, Show, W500 Center, Short.cm URL Shortener
  Return

  URLShortenButtonOK:
    Gui, Submit, NoHide
    result := ShortenURL(SHORT_CM_API_KEY, Domain, LongUrl, Slug, Title, Password)
    if (result = 0 or result = 2)
      Gui, Destroy
  Return

  URLShortenButtonCancel:
    Gui, Destroy
  Return
}

; Get all the available short domains using the Short.cm API
; Returns on success: an array of domains
;         on failure: 1
GetDomains(apiKey)
{
  oWhr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
  oWhr.Open("GET", "https://api.short.cm/api/domains", false)
  oWhr.SetRequestHeader("Authorization", apiKey)
  oWhr.Send()

  if (oWhr.Status != 200) {
    MsgBox, 16, Unknown error, % "An unexpected error occurred. HTTP status code " oWhr.Status ". Response body:`r`r" oWhr.ResponseText
    Return 1
  }

  domains := []

  hostNamePattern = "hostname": *"\K[^"]*
  hostNamePos := 1
  while (hostNamePos := RegExMatch(oWhr.ResponseText, hostNamePattern, hostName, hostNamePos)) {
    domains.Push(hostName)
  }

  Return domains
}

; Shorten a URL using the Short.cm API
; Returns on success: 0
;         on failure: 1 (should retry) or 2 (should not retry)
ShortenURL(apiKey, domain, LongUrl, slug:="", title:="", password:="")
{
  oWhr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
  oWhr.Open("POST", "https://api.short.cm/links", false)
  oWhr.SetRequestHeader("Content-Type", "application/json")
  oWhr.SetRequestHeader("Authorization", apiKey)

  reqBody := "{""domain"":""" domain """,""originalURL"":""" LongUrl """"
  if (slug != "")
    reqBody := reqBody ",""path"":""" slug """"
  if (title != "")
    reqBody := reqBody ",""title"":""" title """"
  ; This currently doesn't seem to work with the API, see workaround below
  ;if (password)
  ;  reqBody := reqBody ",""password"":""" password """"
  reqBody := reqBody "}"
  MsgBox % reqBody
  oWhr.Send(reqBody)

  if (oWhr.Status = 409) {
    MsgBox, 21, Slug duplicate, The selected slug is already in use by another shortened link.
    IfMsgBox Retry
      Return 1
    Return 2
  } else if (oWhr.Status != 200) and (oWhr.Status != 201) {
    MsgBox, 16, Unknown error, % "An unexpected error occurred. HTTP status code " oWhr.Status ". Response body:`r`r" oWhr.ResponseText
    Return 1
  }

  shortUrlPattern = "(secureS|s)hortURL": *"\K[^"]*
  shortUrlPos := RegExMatch(oWhr.ResponseText, shortUrlPattern, shortUrl)
  if (shortUrlPos = 0) {
    MsgBox, 16, Short URL not found, % "The short URL could not be found in the API response. Response body:`r`r" oWhr.ResponseText
    Return 1
  }

  ; API password bug workaround
  ; Modify the existing short URL by extracting the ID from the response of the previous
  ; API call and using it in a call to /links/{id} with the password to use.
  if (password) {
    idPattern = "id": *\K[0-9]*
    RegExMatch(oWhr.ResponseText, idPattern, id)
    updateUrl := "https://api.short.cm/links/" id
    oWhr.Open("POST", updateUrl, false)
    oWhr.SetRequestHeader("Content-Type", "application/json")
    oWhr.SetRequestHeader("Authorization", apiKey)
    updateBody := "{""password"":""" password """}"
    oWhr.Send(updateBody)
  }

  Clipboard := shortUrl
  MsgBox, 64, Successfully shortened, Short URL has been copied to clipboard., 10
  Return 0
}
