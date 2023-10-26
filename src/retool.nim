import
    os,
    nimgl/[glfw, opengl, imgui],
    nimgl/imgui/[impl_opengl, impl_glfw],
    times,
    strformat,
    re,
    parsecfg

const zeroPos = ImVec2(x: 0, y: 0)
const ImVec4* = proc(x: float32, y: float32, z: float32, w: float32): ImVec4 = ImVec4(x: x, y: y, z: z, w: w)
const ImVec2* = proc(x: float32, y: float32): ImVec2 = ImVec2(x: x, y: y)

proc `or`*(x, y: ImGuiWindowFlags): ImGuiWindowFlags =
    (x.int or y.int).ImGuiWindowFlags
proc `or`*(x, y: ImGuiInputTextFlags): ImGuiInputTextFlags =
    (x.int or y.int).ImGuiInputTextFlags

var window: GLFWWindow
var clipboardText: string = ""

# regex, case insnsitive, regex object, replacement, error
var reBuffers = newSeq[(cstring, bool, Regex, cstring, bool)]()
var reOutputBuffer = ""
var redraw = false

proc processText(): string =
  result = clipboardText
  for buffer in reBuffers:
    if buffer[2] != nil and buffer[0].len >= 1:
      result = replace(result, buffer[2], $buffer[3])

proc recalc() = 
  reOutputBuffer = processText()


proc changeEdit(data: ptr ImGuiInputTextCallbackData): int32 {.cdecl, varargs.} =
  defer:
    redraw = true
  var index = cast[int](data[].userData)
  var incoming = $data[].buf
  if incoming.len == 0:
    zeroMem(reBuffers[index][3][0].addr, 2048)
    return 0
  copyMem(reBuffers[index][3][0].addr, incoming[0].addr, incoming.len)
  
  return 0

proc compileRe(data: ptr ImGuiInputTextCallbackData): int32 {.cdecl, varargs.} =
  defer:
    redraw = true
  var index = cast[int](data[].userData)
  var flags: set[RegexFlag]
  if reBuffers[index][1]:
    flags = flags + {RegexFlag.reIgnoreCase}
  var incoming = $data[].buf
  if incoming.len == 0:
    reBuffers[index][2] = nil
    reBuffers[index][4] = true
    return
  copyMem(reBuffers[index][0][0].addr, incoming[0].addr, incoming.len)
  
  try:
    reBuffers[index][2] = re(incoming, flags)
    reBuffers[index][4] = false
  except:
    reBuffers[index][2] = nil
    reBuffers[index][4] = true
  


  return 0.int32

proc addBuffer() = 
  var b1 = cast[cstring](create(char, 2049))
  var b2 = cast[cstring](create(char, 2049))
  reBuffers.add((b1, true, nil, b2, false))

proc addBuffer(regexStr: string, replacement: string, sensitive: bool) =
  var b1 = cast[cstring](create(char, 2049))
  var b2 = cast[cstring](create(char, 2049))
  copyMem(b1[0].addr, regexStr[0].addr, regexStr.len)
  copyMem(b2[0].addr, replacement[0].addr, replacement.len)
  reBuffers.add((b1, sensitive, nil, b2, false))

proc MainWindow() =
  defer:
    if redraw:
      recalc()
      redraw = false
  if clipboardText.len == 0:
    clipboardText = $window.getClipboardString()
    if clipboardText.len == 0:
      quit()
    reOutputBuffer = clipboardText
  if reBuffers.len == 0:
    reBuffers.add((newString(2048).cstring, true, nil, newString(2048).cstring, false))
  igSetNextWindowPos(zeroPos)
  igBegin("Main Window", nil, ImGuiWindowFlags.NoTitleBar or ImGuiWindowFlags.NoResize)
  var mainWinX, mainWinY: int32
  window.getFramebufferSize(addr mainWinX, addr mainWinY)
  igSetWindowSize(ImVec2(x: mainWinX.float32, y: mainwinY.float32))
  var maxwidth = ImVec2(mainWinX.float32 - 12, 0.float32)
  igPushAllowKeyboardFocus(false)
  igInputTextMultiline("##view".cstring, reOutputBuffer.cstring, clipboardText.len.uint, maxwidth, ImGuiInputTextFlags.ReadOnly)
  if igIsItemFocused():
    igSetKeyboardFocusHere(1)
  igPopAllowKeyboardFocus()
  var i: int = 0
  var nuke = false
  for _ in reBuffers:
    igPushId(i.int32)
    igPushFocusScope(i.uint32)

    if igIsKeyReleased('D'.int32) and igGetIo().keyCtrl and igGetFocusedFocusScope() == i.uint32:
      nuke = true

    var color = ImVec4(1, 1, 1, 1)
    if reBuffers[i][4]: color = ImVec4(1, 0, 0, 1)
    igText(&"#{i + 1}")
    igSameLine()
    igPushStyleColor(ImGuiCol.Text, color)
    igPushItemWidth((maxWidth.x - 75) / 2)
    if igIsWindowFocused(ImGuiFocusedFlags.RootAndChildWindows) and not igIsAnyItemActive() and not igIsMouseClicked(ImGuiMouseButton.Left):
      igSetKeyboardFocusHere(0)
    igInputText("##regex".cstring, reBuffers[i][0], 2048, ImGuiInputTextFlags.CallbackEdit, 
      compileRe,
      cast[pointer](i)
    )
    igSameLine()
    igInputText("##replace".cstring, reBuffers[i][3], 2048, ImGuiInputTextFlags.CallbackEdit, 
      changeEdit,
      cast[pointer](i)
    )
    igPopItemWidth()
    igSameLine()
    if igIsKeyReleased('I'.int32) and igGetIo().keyCtrl and igGetFocusedFocusScope() == i.uint32:
      var flags: set[RegexFlag] = {RegexFlag.reStudy}
      reBuffers[i][1] = not reBuffers[i][1]
      if reBuffers[i][1]:
        flags = flags + {RegexFlag.reIgnoreCase}

      reBuffers[i][2] = re($reBuffers[i][0], flags)
      redraw = true
    if igCheckbox("i".cstring, reBuffers[i][1].addr):
      var flags: set[RegexFlag] = {RegexFlag.reStudy}
      if reBuffers[i][1]:
        flags = flags + {RegexFlag.reIgnoreCase}

      reBuffers[i][2] = re($reBuffers[i][0], flags)
      redraw = true
    igPopStyleColor()
    igPopID()
    igPopFocusScope()
    inc i
  igEnd()

  if nuke:
    discard reBuffers.pop()




proc main() =
    doAssert glfwInit()

    glfwWindowHint(GLFWContextVersionMajor, 3)
    glfwWindowHint(GLFWContextVersionMinor, 3)
    glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE)
    glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
    glfwWindowHint(GLFWResizable, GLFW_TRUE)
    glfwWindowHint(GLFW_DECORATED, GLFW_FALSE);


    window = glfwCreateWindow(800, 200, title="Retool")
    if window == nil:
        quit(-1)

    window.makeContextCurrent()

    doAssert glInit()



    let context = igCreateContext()
    var io = igGetIO()
    io[].iniFilename = nil

    doAssert igGlfwInitForOpenGL(window, true)
    doAssert igOpenGL3Init()

    igStyleColorsCherry()

    const frameTime = 0.033

    let configFile = "/tmp/retool.cfg"
    var config: Config
    try:
      config = loadConfig(configFile)
      var i = 0
      while true:
        var sensitive = config.getSectionValue("", &"{i}-i", "NO EXISTO")
        if sensitive == "NO EXISTO":
          break
        var replacement = config.getSectionValue("", &"{i}-repl", "")
        var regex = config.getSectionValue("", &"{i}-re", "")
        addBuffer(regex, replacement, sensitive == "true")
        inc i
    except:
      config = newConfig()
      addBuffer()
    




    var frameTimer = cpuTime() + frameTime
    while not window.windowShouldClose:
        igOpenGL3NewFrame()
        igGlfwNewFrame()
        igNewFrame()

        MainWindow()

        if igIsKeyPressed(igGetKeyIndex(ImguiKey.Escape)):
          window.setWindowShouldClose(true)
        if igIsKeyPressed(igGetKeyIndex(ImguiKey.Enter)):
          window.setClipboardString(reOutputBuffer.cstring)
          window.setWindowShouldClose(true)
          
        if igIsKeyReleased('N'.int32) and io.keyCtrl:
          addBuffer()
          

        igRender()

        glClearColor(0.45f, 0.55f, 0.60f, 1.00f)
        glClear(GL_COLOR_BUFFER_BIT)

        igOpenGL3RenderDrawData(igGetDrawData())

        window.swapBuffers()

        sleep(((max(0, frameTimer - cpuTime())) * 1000).int)
        frameTimer = cpuTime() + frameTime
        glfwPollEvents()

    config = newConfig()
    var i = 0
    for buf in reBuffers:
      config.setSectionKey("", &"{i}-i", if buf[1]: "true" else: "false")
      config.setSectionKey("", &"{i}-repl", $buf[3])
      config.setSectionKey("", &"{i}-re", $buf[0])
      inc i
    writeConfig(config, configFile)

    igOpenGL3Shutdown()
    igGlfwShutdown()
    context.igDestroyContext()

    window.destroyWindow()
    glfwTerminate()

main()
