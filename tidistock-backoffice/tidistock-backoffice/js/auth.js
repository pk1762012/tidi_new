const apiBaseUrl = "";

$(document).ready(function(){

    const token = localStorage.getItem("token"); // or your key
    if (token) {
        window.location.href = "dashboard.html";
    }


    $("#loginForm").submit(function(e){
        e.preventDefault();

        let phone = $("#phone_number").val().trim();
        let password = $("#password").val().trim();

        // Clear previous errors
        $("#phoneError").text("");
        $("#passwordError").text("");

        let isValid = true;

        // Phone validation
        if (!/^\d{10}$/.test(phone)) {
            $("#phoneError").text("Phone number must be exactly 10 digits.");
            isValid = false;
        }

        // Password validation
        if (password.length === 0) {
            $("#passwordError").text("Password is required.");
            isValid = false;
        }

        if (!isValid) return;

        showLoading(); // Show loading before AJAX

        $.ajax({
            url: apiBaseUrl + "/api/admin/login",
            method: "POST",
            contentType: "application/json",
            data: JSON.stringify({ phone_number: phone, password }),
            success: function(response){
                if (response.roles && response.roles.includes("ROLE_ADMIN")) {
                    localStorage.setItem("token", response.access_token);
                    localStorage.setItem("roles", JSON.stringify(response.roles));
                    localStorage.setItem("url", apiBaseUrl);
                    window.location.href = "dashboard.html";
                } else {
                    $("#passwordError").text("Only admin accounts can log in.");
                }
            },
            error: function(){
                $("#passwordError").text("Invalid credentials.");
            },
            complete: function(){
                setTimeout(hideLoading, 200) // Always hide after request finishes
            }
        });
    });
});

function showLoading(){ $("body").append('<div id="loadingOverlay" style="position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(255,255,255,0.6);z-index:9999;display:flex;align-items:center;justify-content:center;"><div class="spinner-border text-primary" role="status"><span class="visually-hidden">Loading...</span></div></div>'); }
function hideLoading(){ $("#loadingOverlay").remove(); }