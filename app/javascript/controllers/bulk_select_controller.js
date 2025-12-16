import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="bulk-select"
export default class extends Controller {
  static targets = ["checkbox", "selectAll", "deleteButton", "counter", "container", "form", "hiddenInputs"]
  static values = { keyType: String }

  connect() {
    this.updateCount()

    // Add form submit handler to inject selected minion IDs
    if (this.hasFormTarget) {
      this.formTarget.addEventListener('submit', this.injectSelectedIds.bind(this))
    }
  }

  disconnect() {
    if (this.hasFormTarget) {
      this.formTarget.removeEventListener('submit', this.injectSelectedIds.bind(this))
    }
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

  // Inject selected minion IDs as hidden inputs before form submission
  injectSelectedIds(event) {
    if (!this.hasHiddenInputsTarget) return

    // Clear any existing hidden inputs
    this.hiddenInputsTarget.innerHTML = ''

    // Get selected checkboxes and create hidden inputs for their minion IDs
    const selectedCheckboxes = this.checkboxTargets.filter(cb => cb.checked)

    selectedCheckboxes.forEach(checkbox => {
      const minionId = checkbox.dataset.minionId
      if (minionId) {
        const input = document.createElement('input')
        input.type = 'hidden'
        input.name = 'minion_ids[]'
        input.value = minionId
        this.hiddenInputsTarget.appendChild(input)
      }
    })

    // If no checkboxes selected, prevent submission
    if (selectedCheckboxes.length === 0) {
      event.preventDefault()
      alert('No keys selected')
    }
  }
}
