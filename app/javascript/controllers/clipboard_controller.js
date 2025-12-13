import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="clipboard"
export default class extends Controller {
  static targets = ["source", "button", "icon"]
  static values = {
    successDuration: { type: Number, default: 2000 }
  }

  connect() {
    // Check for Clipboard API support
    if (!navigator.clipboard) {
      console.warn("Clipboard API not supported")
    }
  }

  copy(event) {
    event.preventDefault()

    const text = this.sourceTarget.value || this.sourceTarget.textContent || this.sourceTarget.innerText

    // Try modern Clipboard API first
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text)
        .then(() => this.copied())
        .catch(err => this.fallbackCopy(text))
    } else {
      this.fallbackCopy(text)
    }
  }

  fallbackCopy(text) {
    // Fallback for older browsers
    const textArea = document.createElement("textarea")
    textArea.value = text
    textArea.style.position = "fixed"
    textArea.style.left = "-999999px"
    textArea.style.top = "-999999px"
    document.body.appendChild(textArea)
    textArea.focus()
    textArea.select()

    try {
      const successful = document.execCommand('copy')
      if (successful) {
        this.copied()
      } else {
        console.error("Fallback copy failed")
      }
    } catch (err) {
      console.error("Fallback copy error:", err)
    }

    document.body.removeChild(textArea)
  }

  copied() {
    // Swap icon to checkmark
    if (this.hasIconTarget) {
      const originalIcon = this.iconTarget.innerHTML
      this.iconTarget.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
          <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" />
        </svg>
      `

      // Add success state to button
      if (this.hasButtonTarget) {
        this.buttonTarget.classList.add("btn-success")
      }

      // Revert after duration
      setTimeout(() => {
        this.iconTarget.innerHTML = originalIcon
        if (this.hasButtonTarget) {
          this.buttonTarget.classList.remove("btn-success")
        }
      }, this.successDurationValue)
    }
  }
}
