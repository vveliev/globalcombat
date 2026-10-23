// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Player-to-player chat — floating chat windows + the "chat:<id>" push channel.
import "./chat.js"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/global_combat"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// `JS.dispatch("gc:reset-form", to: "#some-form")` from a phx-submit: clear the form
// the moment it is sent. LiveView leaves the focused input's value alone when it
// patches, so a server-side blank form by itself does not empty the box.
window.addEventListener("gc:reset-form", e => {
  if (e.target instanceof HTMLFormElement) e.target.reset()
})

// The order panel's quick picks (1 · Half · Max · ±1) are server events that
// rewrite the draft amount, but the submit reads the inputs in the DOM. Mirror the
// pick into the inputs synchronously so a quick Assign/Attack after a pick sends
// the picked amount even when the server's diff has not landed yet.
document.addEventListener("click", e => {
  const pick = e.target.closest("#order-stepper [data-amount], #order-stepper [data-amount-delta]")
  if (!pick) return
  const form = pick.closest("form")
  const number = form && form.querySelector("#order-amount")
  if (!number) return
  const range = form.querySelector("#order-amount-range")
  let amount
  if (pick.dataset.amount !== undefined) {
    amount = parseInt(pick.dataset.amount, 10)
  } else {
    amount = (parseInt(number.value, 10) || 0) + parseInt(pick.dataset.amountDelta, 10)
  }
  if (Number.isNaN(amount)) return
  amount = Math.max(amount, 0)
  number.value = String(amount)
  if (range) range.value = String(Math.min(amount, parseInt(range.max, 10) || amount))
})

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

