/**
 * DaisyUI Theme Switcher
 * Handles dynamic theme switching with localStorage persistence
 */

document.addEventListener('DOMContentLoaded', function() {
  // Get current theme from localStorage or default to 'night'
  const currentTheme = localStorage.getItem('daisyui-theme') || 'night';

  // Set initial active state on theme options
  updateActiveThemeIndicator(currentTheme);

  // Add click event listeners to all theme options
  document.querySelectorAll('.theme-option').forEach(function(element) {
    element.addEventListener('click', function(e) {
      e.preventDefault();
      const selectedTheme = this.getAttribute('data-theme');

      // Update the data-theme attribute on html element
      document.documentElement.setAttribute('data-theme', selectedTheme);

      // Save to localStorage
      localStorage.setItem('daisyui-theme', selectedTheme);

      // Update active indicator
      updateActiveThemeIndicator(selectedTheme);

      // Add smooth transition effect
      document.documentElement.classList.add('theme-transition');
      setTimeout(() => {
        document.documentElement.classList.remove('theme-transition');
      }, 300);

      // Close the dropdown after selection (optional)
      const dropdown = this.closest('.dropdown');
      if (dropdown) {
        const elem = dropdown.querySelector('[tabindex="0"]');
        if (elem) elem.blur();
      }

      // Dispatch custom event for charts or other components to update
      window.dispatchEvent(new CustomEvent('themeChanged', {
        detail: { theme: selectedTheme }
      }));
    });
  });
});

/**
 * Update the active class on theme selector items
 */
function updateActiveThemeIndicator(themeName) {
  document.querySelectorAll('.theme-option').forEach(function(element) {
    if (element.getAttribute('data-theme') === themeName) {
      element.classList.add('active');
    } else {
      element.classList.remove('active');
    }
  });
}

/**
 * Get DaisyUI CSS variable values
 * Useful for charts and other components that need theme colors
 */
function getThemeColor(variable) {
  return getComputedStyle(document.documentElement).getPropertyValue(variable).trim();
}

/**
 * Export theme colors for use in charts
 */
window.VeracityTheme = {
  getColor: function(colorName) {
    const colorMap = {
      'primary': '--p',
      'secondary': '--s',
      'accent': '--a',
      'neutral': '--n',
      'base-100': '--b1',
      'base-200': '--b2',
      'base-300': '--b3',
      'base-content': '--bc',
      'info': '--in',
      'success': '--su',
      'warning': '--wa',
      'error': '--er'
    };

    const variable = colorMap[colorName];
    if (variable) {
      return `hsl(${getThemeColor(variable)})`;
    }
    return null;
  },

  getCurrentTheme: function() {
    return localStorage.getItem('daisyui-theme') || 'night';
  }
};
