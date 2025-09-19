// Template for chart data structure
const chartDataTemplate = {
    transportTypes: {
        labels: [],
        data: []
    },
    gatewayRegions: {
        labels: [],
        data: []
    },
    clientTypes: {
        labels: [],
        data: []
    },
    clientOSs: {
        labels: [],
        data: []
    }
};

// Data containers for different time ranges
let monthlyData = JSON.parse(JSON.stringify(chartDataTemplate));
let weeklyData = JSON.parse(JSON.stringify(chartDataTemplate));
let dailyData = JSON.parse(JSON.stringify(chartDataTemplate));

// Function to update data for a specific time range
function updateChartData(timeRange, newData) {
    switch(timeRange) {
        case 'monthly':
            monthlyData = newData;
            break;
        case 'weekly':
            weeklyData = newData;
            break;
        case 'daily':
            dailyData = newData;
            break;
        default:
            console.error(`Invalid time range: ${timeRange}`);
    }
}
