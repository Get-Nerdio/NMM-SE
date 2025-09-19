function createChart(id, data, labels) {
    const ctx = document.getElementById(id);
    if (!ctx) {
        console.error(`Canvas element not found: ${id}`);
        return null;
    }

    return new Chart(ctx, {
        type: 'pie',
        data: {
            labels: labels,
            datasets: [{
                data: data,
                backgroundColor: chartColors
            }]
        },
        options: chartOptions
    });
}

function updateSummaries(timeRange) {
    const data = timeRange === 'weekly' ? weeklyData :
                timeRange === 'daily' ? dailyData : monthlyData;

    // Update analytics summaries
    ['transportTypes', 'gatewayRegions', 'clientTypes', 'clientOSs'].forEach(type => {
        const summaryHtml = data[type].labels.map((label, index) => {
            const value = data[type].data[index];
            return `<div class="analytics-list-item">
                <span class="analytics-label">${label}</span>
                <span class="analytics-value">${value.toFixed(1)}%</span>
            </div>`;
        }).join('\n');
        const element = document.getElementById(`${type}Summary`);
        if (element) {
            element.innerHTML = summaryHtml;
        }
    });
}

function updateCharts(timeRange) {
    const data = timeRange === 'weekly' ? weeklyData :
                timeRange === 'daily' ? dailyData : monthlyData;

    // Update time range description
    const timeDesc = timeRange === 'weekly' ? 'Last 4 Weeks' :
                   timeRange === 'daily' ? 'Last 7 Days' : 'Last 2 Months';
    document.querySelectorAll('.chart-info').forEach(el => {
        const baseText = el.textContent.split('(')[0].trim();
        el.textContent = `${baseText} (${timeDesc})`;
    });

    // Update summaries
    updateSummaries(timeRange);

    // Destroy existing charts
    Object.entries(charts).forEach(([key, chart]) => {
        if (chart) {
            chart.destroy();
            charts[key] = null;
        }
    });

    // Create new charts
    charts.transportTypes = createChart('transportTypesChart', 
        data.transportTypes.data, data.transportTypes.labels);
    charts.gatewayRegions = createChart('gatewayRegionsChart',
        data.gatewayRegions.data, data.gatewayRegions.labels);
    charts.clientTypes = createChart('clientTypesChart',
        data.clientTypes.data, data.clientTypes.labels);
    charts.clientOS = createChart('clientOSChart',
        data.clientOSs.data, data.clientOSs.labels);
}

// Initialize charts with monthly data when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    updateCharts('monthly');

    // Add event listener to time range selector
    const selector = document.getElementById('timeRange');
    if (selector) {
        selector.addEventListener('change', function(e) {
            updateCharts(e.target.value);
        });
    }
});
