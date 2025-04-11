/**
 * Microsoft 365 License Report - Interactive Features
 */

// Add license type classification based on name patterns
function classifyLicenseType(licenseName) {
    const lowerName = licenseName.toLowerCase();
    
    if (lowerName.includes('enterprise') || 
        lowerName.includes('e3') || 
        lowerName.includes('e5') || 
        lowerName.includes('e1')) {
        return 'enterprise';
    } else if (lowerName.includes('business') || 
               lowerName.includes('premium') || 
               lowerName.includes('standard')) {
        return 'business';
    } else if (lowerName.includes('frontline') || 
               lowerName.includes('f1') || 
               lowerName.includes('f3')) {
        return 'frontline';
    } else {
        return 'other';
    }
}

// Calculate license utilization percentages
function calculateUtilization() {
    // Calculate overall license utilization
    let totalLicenses = 0;
    let totalConsumed = 0;
    
    licenseSummaryData.forEach(license => {
        if (!isNaN(license.TotalLicenses)) {
            totalLicenses += parseInt(license.TotalLicenses);
        }
        if (!isNaN(license.ConsumedLicenses)) {
            totalConsumed += parseInt(license.ConsumedLicenses);
        }
    });
    
    // Update the summary numbers at the top
    document.getElementById('totalLicenses').textContent = totalLicenses.toLocaleString();
    document.getElementById('assignedLicenses').textContent = totalConsumed.toLocaleString();
    document.getElementById('availableLicenses').textContent = (totalLicenses - totalConsumed).toLocaleString();
    
    if (totalLicenses - totalConsumed < 0) {
        document.getElementById('availableLicenses').classList.add('negative-available');
    } else if (totalLicenses - totalConsumed <= 10) {
        document.getElementById('availableLicenses').classList.add('low-available');
    }
    
    // Calculate individual license utilization
    licenseSummaryData.forEach(license => {
        license.utilizationPercentage = license.TotalLicenses > 0 
            ? (license.ConsumedLicenses / license.TotalLicenses * 100).toFixed(1) 
            : 0;
    });
}

// Add visual indicators to the table rows
function enhanceTableDisplay() {
    const table = document.getElementById('licenseSummaryTable');
    if (!table) return;
    
    // Get all rows except the header
    const rows = Array.from(table.querySelectorAll('tbody tr'));
    
    rows.forEach(row => {
        // Get the license name and type cells
        const nameCell = row.cells[0];
        const licenseType = classifyLicenseType(nameCell.textContent);
        
        // Add type indicator
        const indicator = document.createElement('span');
        indicator.className = `license-type-indicator license-type-${licenseType}`;
        nameCell.insertBefore(indicator, nameCell.firstChild);
        
        // Add available class for styling
        const availableCell = row.cells[5];
        availableCell.className = 'available-cell';
        
        // Add tooltips for better information
        const consumed = parseInt(row.cells[4].textContent);
        const total = parseInt(row.cells[3].textContent);
        if (!isNaN(consumed) && !isNaN(total) && total > 0) {
            const percentage = ((consumed / total) * 100).toFixed(1);
            row.cells[4].setAttribute('title', `${percentage}% utilized`);
        }
    });
}

// Create a utilization dashboard
function createUtilizationDashboard() {
    // Only create if the container exists
    const dashboardContainer = document.getElementById('utilizationDashboard');
    if (!dashboardContainer) return;
    
    // Create utilization cards for each license
    licenseSummaryData.forEach(license => {
        if (license.TotalLicenses > 0) {
            const percentage = license.utilizationPercentage;
            const card = document.createElement('div');
            card.className = 'col-md-3 mb-3';
            
            let colorClass = 'bg-success';
            if (percentage > 90) colorClass = 'bg-danger';
            else if (percentage > 75) colorClass = 'bg-warning';
            
            card.innerHTML = `
                <div class="card h-100">
                    <div class="card-body text-center">
                        <h5 class="card-title">${license.LicenseName}</h5>
                        <div class="progress mb-3">
                            <div class="progress-bar ${colorClass}" 
                                 role="progressbar" 
                                 style="width: ${percentage}%" 
                                 aria-valuenow="${percentage}" 
                                 aria-valuemin="0" 
                                 aria-valuemax="100">${percentage}%</div>
                        </div>
                        <p class="card-text">
                            ${license.ConsumedLicenses} of ${license.TotalLicenses} used
                        </p>
                    </div>
                </div>
            `;
            dashboardContainer.appendChild(card);
        }
    });
}

// Print the report with proper formatting
function printReport() {
    window.print();
}

// Document ready handler - initialize everything
document.addEventListener('DOMContentLoaded', function() {
    // Skip if no license data is available
    if (!licenseSummaryData || licenseSummaryData.length === 0) return;
    
    // Calculate utilization metrics
    calculateUtilization();
    
    // Enhance the table display
    enhanceTableDisplay();
    
    // Create utilization dashboard if container exists
    createUtilizationDashboard();
    
    // Add print button functionality
    const printBtn = document.getElementById('printReportBtn');
    if (printBtn) {
        printBtn.addEventListener('click', printReport);
    }
    
    // Add table sorting and filtering if DataTables is available
    if (typeof $.fn.DataTable !== 'undefined') {
        // Configuration is handled in the inline script
    }
}); 