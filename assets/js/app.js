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
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/luca_gymapp"
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

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

const turnstileScriptUrl = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
let turnstileScriptPromise = null

const setRegisterSubmitButtonState = (submitButton, enabled) => {
  if (!submitButton) {
    return
  }

  submitButton.disabled = !enabled

  if (enabled) {
    submitButton.classList.remove("cursor-not-allowed", "bg-neutral-300")
    submitButton.classList.add("bg-neutral-900", "hover:bg-neutral-800")
  } else {
    submitButton.classList.add("cursor-not-allowed", "bg-neutral-300")
    submitButton.classList.remove("bg-neutral-900", "hover:bg-neutral-800")
  }
}

const updateRegisterSubmitState = form => {
  if (!form) {
    return
  }

  const submitButton = form.querySelector("[data-turnstile-submit]")
  const consentCheckbox = form.querySelector("[data-register-terms-checkbox]")
  const tokenInput = form.querySelector("#turnstile-token")
  const hasTurnstileWidget = !!form.querySelector("[data-turnstile]")

  const consentAccepted = consentCheckbox ? consentCheckbox.checked : true
  const hasTurnstileToken = !hasTurnstileWidget || !!(tokenInput && tokenInput.value)

  setRegisterSubmitButtonState(submitButton, consentAccepted && hasTurnstileToken)
}

const ensureTurnstileLoaded = () => {
  if (window.turnstile) {
    return Promise.resolve()
  }

  if (turnstileScriptPromise) {
    return turnstileScriptPromise
  }

  turnstileScriptPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = turnstileScriptUrl
    script.async = true
    script.defer = true
    script.onload = () => resolve()
    script.onerror = () => reject(new Error("Turnstile failed to load"))
    document.head.appendChild(script)
  })

  return turnstileScriptPromise
}

const renderTurnstileWidgets = () => {
  const widgets = document.querySelectorAll("[data-turnstile]")
  if (widgets.length === 0) {
    return
  }

  widgets.forEach(widget => {
    const form = widget.closest("form")
    updateRegisterSubmitState(form)
  })

  ensureTurnstileLoaded()
    .then(() => {
      widgets.forEach(widget => {
        if (widget.dataset.rendered === "true") {
          return
        }

        const sitekey = widget.dataset.sitekey
        if (!sitekey) {
          return
        }

        const form = widget.closest("form")
        const tokenInput = form && form.querySelector("#turnstile-token")

        window.turnstile.render(widget, {
          sitekey,
          callback: token => {
            if (tokenInput) {
              tokenInput.value = token
            }
            updateRegisterSubmitState(form)
          },
          "expired-callback": () => {
            if (tokenInput) {
              tokenInput.value = ""
            }
            updateRegisterSubmitState(form)
          },
          "error-callback": () => {
            if (tokenInput) {
              tokenInput.value = ""
            }
            updateRegisterSubmitState(form)
          },
        })

        widget.dataset.rendered = "true"
      })
    })
    .catch(() => {
      widgets.forEach(widget => {
        const form = widget.closest("form")
        const tokenInput = form && form.querySelector("#turnstile-token")

        if (tokenInput) {
          tokenInput.value = ""
        }

        updateRegisterSubmitState(form)
      })
    })
}

document.addEventListener("DOMContentLoaded", renderTurnstileWidgets)
window.addEventListener("phx:page-loading-stop", renderTurnstileWidgets)

const initRegisterConsentForms = () => {
  const forms = document.querySelectorAll("#register-form")

  forms.forEach(form => {
    const consentCheckbox = form.querySelector("[data-register-terms-checkbox]")
    if (!consentCheckbox) {
      return
    }

    updateRegisterSubmitState(form)

    if (form.dataset.registerConsentBound === "true") {
      return
    }

    consentCheckbox.addEventListener("change", () => {
      updateRegisterSubmitState(form)
    })

    form.dataset.registerConsentBound = "true"
  })
}

document.addEventListener("DOMContentLoaded", initRegisterConsentForms)
window.addEventListener("phx:page-loading-stop", initRegisterConsentForms)

const togglePasswordField = toggleButton => {
  const fieldContainer = toggleButton.closest("[data-password-field]")
  if (!fieldContainer) {
    return
  }

  const passwordInput = fieldContainer.querySelector("[data-password-input]")
  if (!passwordInput) {
    return
  }

  const showIcon = toggleButton.querySelector("[data-password-show-icon]")
  const hideIcon = toggleButton.querySelector("[data-password-hide-icon]")
  const showPassword = passwordInput.type === "password"

  passwordInput.type = showPassword ? "text" : "password"
  toggleButton.setAttribute("aria-label", showPassword ? "Hide password" : "Show password")

  if (showIcon && hideIcon) {
    showIcon.classList.toggle("hidden", showPassword)
    hideIcon.classList.toggle("hidden", !showPassword)
  }
}

document.addEventListener("click", event => {
  const toggleButton = event.target.closest("[data-password-toggle]")
  if (!toggleButton) {
    return
  }

  event.preventDefault()
  togglePasswordField(toggleButton)
})

const initAszfPurchaseForms = () => {
  const forms = document.querySelectorAll(".purchase-terms-form")

  forms.forEach(form => {
    const checkboxes = form.querySelectorAll("[data-aszf-checkbox]")
    const submitButton = form.querySelector("[data-aszf-submit]")

    if (checkboxes.length === 0 || !submitButton) {
      return
    }

    const setSubmitState = () => {
      const allAccepted = Array.from(checkboxes).every(checkbox => checkbox.checked)
      submitButton.disabled = !allAccepted
    }

    setSubmitState()

    if (form.dataset.aszfBound === "true") {
      return
    }

    checkboxes.forEach(checkbox => {
      checkbox.addEventListener("change", setSubmitState)
    })

    form.dataset.aszfBound = "true"
  })
}

document.addEventListener("DOMContentLoaded", initAszfPurchaseForms)
window.addEventListener("phx:page-loading-stop", initAszfPurchaseForms)

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
