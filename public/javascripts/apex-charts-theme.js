/**
 * ApexCharts DaisyUI Theme Integration
 * Automatically adapts ApexCharts to DaisyUI theme colors
 */

window.ApexChartsTheme = {
  /**
   * Get base chart options that work with all DaisyUI themes
   * @param {Object} customOptions - Custom options to merge with base
   * @returns {Object} Chart configuration
   */
  getBaseOptions: function(customOptions = {}) {
    const baseOptions = {
      chart: {
        background: 'transparent',
        foreColor: this.getColor('base-content'),
        fontFamily: 'Inter, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif',
        toolbar: {
          show: true,
          tools: {
            download: true,
            selection: true,
            zoom: true,
            zoomin: true,
            zoomout: true,
            pan: true,
            reset: true
          }
        }
      },
      colors: [
        this.getColor('primary'),
        this.getColor('secondary'),
        this.getColor('accent'),
        this.getColor('info'),
        this.getColor('success'),
        this.getColor('warning'),
        this.getColor('error')
      ],
      grid: {
        borderColor: this.getColor('base-content', 0.1),
        strokeDashArray: 3
      },
      xaxis: {
        labels: {
          style: {
            colors: this.getColor('base-content', 0.6)
          }
        },
        axisBorder: {
          color: this.getColor('base-content', 0.2)
        },
        axisTicks: {
          color: this.getColor('base-content', 0.2)
        }
      },
      yaxis: {
        labels: {
          style: {
            colors: this.getColor('base-content', 0.6)
          }
        }
      },
      legend: {
        labels: {
          colors: this.getColor('base-content', 0.8)
        }
      },
      tooltip: {
        theme: this.isLightTheme() ? 'light' : 'dark',
        style: {
          fontSize: '12px',
          fontFamily: 'Inter, sans-serif'
        }
      },
      dataLabels: {
        style: {
          colors: [this.getColor('base-content')]
        }
      }
    };

    return this.mergeDeep(baseOptions, customOptions);
  },

  /**
   * Get DaisyUI color as HSL string
   * @param {string} colorName - Color name (e.g., 'primary', 'success')
   * @param {number} opacity - Optional opacity value (0-1)
   * @returns {string} HSL color string
   */
  getColor: function(colorName, opacity = 1) {
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
      const value = getComputedStyle(document.documentElement).getPropertyValue(variable).trim();
      if (opacity < 1) {
        return `hsl(${value} / ${opacity})`;
      }
      return `hsl(${value})`;
    }
    return colorName; // Return as-is if not found
  },

  /**
   * Check if current theme is light or dark
   * @returns {boolean} True if light theme
   */
  isLightTheme: function() {
    const lightThemes = ['light', 'cupcake', 'bumblebee', 'emerald', 'corporate',
                         'retro', 'cyberpunk', 'valentine', 'garden', 'lofi',
                         'pastel', 'fantasy', 'wireframe', 'cmyk', 'autumn',
                         'acid', 'lemonade', 'winter'];
    const currentTheme = localStorage.getItem('daisyui-theme') || 'night';
    return lightThemes.includes(currentTheme);
  },

  /**
   * Get pre-configured options for line charts
   * @param {Object} customOptions - Custom options to override
   * @returns {Object} Line chart configuration
   */
  getLineChartOptions: function(customOptions = {}) {
    return this.getBaseOptions({
      chart: {
        type: 'line',
        height: 350,
        zoom: {
          enabled: true
        }
      },
      stroke: {
        curve: 'smooth',
        width: 2
      },
      markers: {
        size: 4,
        hover: {
          size: 6
        }
      },
      ...customOptions
    });
  },

  /**
   * Get pre-configured options for area charts
   * @param {Object} customOptions - Custom options to override
   * @returns {Object} Area chart configuration
   */
  getAreaChartOptions: function(customOptions = {}) {
    return this.getBaseOptions({
      chart: {
        type: 'area',
        height: 350,
        zoom: {
          enabled: false
        }
      },
      stroke: {
        curve: 'smooth',
        width: 2
      },
      fill: {
        type: 'gradient',
        gradient: {
          shadeIntensity: 1,
          opacityFrom: 0.4,
          opacityTo: 0.1,
          stops: [0, 90, 100]
        }
      },
      ...customOptions
    });
  },

  /**
   * Get pre-configured options for bar charts
   * @param {Object} customOptions - Custom options to override
   * @returns {Object} Bar chart configuration
   */
  getBarChartOptions: function(customOptions = {}) {
    return this.getBaseOptions({
      chart: {
        type: 'bar',
        height: 350
      },
      plotOptions: {
        bar: {
          borderRadius: 4,
          horizontal: false,
          columnWidth: '60%'
        }
      },
      ...customOptions
    });
  },

  /**
   * Get pre-configured options for pie/donut charts
   * @param {Object} customOptions - Custom options to override
   * @returns {Object} Pie chart configuration
   */
  getPieChartOptions: function(customOptions = {}) {
    return this.getBaseOptions({
      chart: {
        type: 'donut',
        height: 350
      },
      plotOptions: {
        pie: {
          donut: {
            size: '70%',
            labels: {
              show: true,
              name: {
                color: this.getColor('base-content', 0.8)
              },
              value: {
                color: this.getColor('base-content'),
                fontSize: '22px',
                fontWeight: 600
              },
              total: {
                show: true,
                color: this.getColor('base-content', 0.6)
              }
            }
          }
        }
      },
      legend: {
        position: 'bottom'
      },
      ...customOptions
    });
  },

  /**
   * Deep merge two objects
   * @param {Object} target - Target object
   * @param {Object} source - Source object
   * @returns {Object} Merged object
   */
  mergeDeep: function(target, source) {
    const output = Object.assign({}, target);
    if (this.isObject(target) && this.isObject(source)) {
      Object.keys(source).forEach(key => {
        if (this.isObject(source[key])) {
          if (!(key in target)) {
            Object.assign(output, { [key]: source[key] });
          } else {
            output[key] = this.mergeDeep(target[key], source[key]);
          }
        } else {
          Object.assign(output, { [key]: source[key] });
        }
      });
    }
    return output;
  },

  /**
   * Check if value is an object
   * @param {*} item - Value to check
   * @returns {boolean} True if object
   */
  isObject: function(item) {
    return item && typeof item === 'object' && !Array.isArray(item);
  }
};

/**
 * Listen for theme changes and update all charts
 */
window.addEventListener('themeChanged', function(event) {
  // Dispatch a custom event that charts can listen to for updating
  console.log('Theme changed to:', event.detail.theme);

  // If you have charts stored globally, you can update them here
  if (window.apexChartInstances) {
    window.apexChartInstances.forEach(function(chart) {
      const newOptions = ApexChartsTheme.getBaseOptions();
      chart.updateOptions(newOptions, false, true);
    });
  }
});

/**
 * Example Usage:
 *
 * // Basic line chart with theme support
 * const options = ApexChartsTheme.getLineChartOptions({
 *   series: [{
 *     name: 'CPU Usage',
 *     data: [30, 40, 35, 50, 49, 60, 70, 91, 125]
 *   }],
 *   xaxis: {
 *     categories: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep']
 *   }
 * });
 *
 * const chart = new ApexCharts(document.querySelector("#chart"), options);
 * chart.render();
 *
 * // Store chart instance for theme updates
 * if (!window.apexChartInstances) window.apexChartInstances = [];
 * window.apexChartInstances.push(chart);
 */
