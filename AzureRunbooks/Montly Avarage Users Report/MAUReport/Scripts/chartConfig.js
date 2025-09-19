const chartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
        legend: {
            position: 'right',
            labels: {
                boxWidth: 12,
                padding: 10,
                font: {
                    size: 11
                }
            }
        },
        tooltip: {
            callbacks: {
                label: function(context) {
                    let label = context.label || '';
                    let value = context.raw || 0;
                    return `${label}: ${value.toFixed(1)}%`;
                }
            }
        }
    }
};

const chartColors = [
    '#1B9CB9', '#D7DF23', '#13BA7C', '#1D3557', '#FF6B6B',
    '#4ECDC4', '#45B7D1', '#96CEB4', '#FFEEAD', '#FF9F1C'
];

let charts = {
    transportTypes: null,
    gatewayRegions: null,
    clientTypes: null,
    clientOS: null
};
