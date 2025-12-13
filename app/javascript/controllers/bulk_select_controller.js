import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="bulk-select"
export default class extends Controller {
  static targets = ["checkbox", "selectAll", "deleteButton", "counter", "container"]

  connect() {
    this.updateCount()
  }

  toggleAll(event) {
    const checked = event.target.checked
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = checked
    })
    this.updateCount()
  }

  updateCount() {
    const selectedCount = this.checkboxTargets.filter(cb => cb.checked).length
    const totalCount = this.checkboxTargets.length

    // Update counter text
    if (this.hasCounterTarget) {
      this.counterTarget.textContent = `${selectedCount} selected`
    }

    // Enable/disable delete button
    if (this.hasDeleteButtonTarget) {
      this.deleteButtonTarget.disabled = selectedCount === 0
    }

    // Update select all checkbox state
    if (this.hasSelectAllTarget) {
      if (selectedCount === 0) {
        this.selectAllTarget.checked = false
        this.selectAllTarget.indeterminate = false
      } else if (selectedCount === totalCount) {
        this.selectAllTarget.checked = true
        this.selectAllTarget.indeterminate = false
      } else {
        this.selectAllTarget.checked = false
        this.selectAllTarget.indeterminate = true
      }
    }
  }
}
