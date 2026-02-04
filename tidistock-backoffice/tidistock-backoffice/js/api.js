function checkAuth(){
    const token = localStorage.getItem("token");
    if(!token){
        window.location.href = "login.html";
    }
}

function getAuthHeaders(){
    return {
        "Authorization": "Bearer " + localStorage.getItem("token")
    };
}

function getStatus() {
    showLoading()
    $.ajax({
        url: localStorage.getItem("url").replace(/\/$/, "") + "/api/admin/dashboard_stats",
        method: "GET",
        headers: getAuthHeaders(),
        success: function (res) {
            setTimeout(hideLoading, 200)
            var d = res.data || res;
            animateCount('activeUsersCount', d.activeUsers);
            animateCount('totalSubs', d.subscribed.total);
            animateCount('monthlySubs', d.subscribed.monthly);
            animateCount('sixMonthSubs', d.subscribed.sixMonths);
            animateCount('annualSubs', d.subscribed.annual);

        },
        error: function (xhr) {
            if (xhr.status === 401) {
                localStorage.clear()
                window.location.href = "login.html";
            } else {
                setTimeout(hideLoading, 200)
                console.error("Error fetching status:", xhr.responseText);
            }
        },
        complete: function () {
            setTimeout(hideLoading, 200)
        }

    });
}

function showLoading(){ $("body").append('<div id="loadingOverlay" style="position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(255,255,255,0.6);z-index:9999;display:flex;align-items:center;justify-content:center;"><div class="spinner-border text-primary" role="status"><span class="visually-hidden">Loading...</span></div></div>'); }
function hideLoading(){ $("#loadingOverlay").remove(); }





