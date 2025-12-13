import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="auto-refresh"
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 30000 } // 30 seconds default
  }

  connect() {
    this.startRefreshing()
    this.setupVisibilityHandler()
  }

  disconnect() {
    this.stopRefreshing()
  }

  startRefreshing() {
    // Only start if not already running
    if (this.refreshTimer) return

    this.refreshTimer = setInterval(() => {
      // Only refresh if page is visible
      if (!document.hidden) {
        this.refresh()
      }
    }, this.intervalValue)
  }

  stopRefreshing() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = null
    }
  }

  async refresh() {
    if (!this.hasUrlValue) return

    try {
      const response = await fetch(this.urlValue, {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-CSRF-Token': this.csrfToken
        }
      })

      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      }
    } catch (error) {
      console.error('Auto-refresh failed:', error)
    }
  }

  setupVisibilityHandler() {
    this.visibilityHandler = () => {
      if (document.hidden) {
        // Page is hidden, pause refreshing
        this.stopRefreshing()
      } else {
        // Page is visible again, resume refreshing
        this.startRefreshing()
        // Refresh immediately when returning to tab
        this.refresh()
      }
    }

    document.addEventListener('visibilitychange', this.visibilityHandler)
  }

  get csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ''
  }
}
