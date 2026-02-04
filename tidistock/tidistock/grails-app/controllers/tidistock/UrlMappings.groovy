package tidistock

class UrlMappings {

    static mappings = {
        /*delete "/$controller/$id(.$format)?"(action:"delete")
        get "/$controller(.$format)?"(action:"index")
        get "/$controller/$id(.$format)?"(action:"show")
        post "/$controller(.$format)?"(action:"save")
        put "/$controller/$id(.$format)?"(action:"update")
        patch "/$controller/$id(.$format)?"(action:"patch")*/
        post "/api/user/create" (controller: 'registration', action: 'create')
        get "/api/user/login/$phoneNumber" (controller: 'registration', action: 'login')
        get "/api/user/trigger_verification/$id" (controller: 'registration', action: 'triggerVerification')
        get "/api/user/verify/$userName/$otp" (controller: 'registration', action: 'verifyUser')
        get "/api/user/validate/$phoneNumber" (controller: 'registration', action: 'validateUser')
        post "/api/user/update_device_details" (controller: 'user', action: 'updateDeviceDetails')
        get "/api/user" (controller: 'user', action: 'getUser')
        patch "/api/user/update" (controller: 'user', action: 'updateUserDetails')
        delete "/api/user" (controller: 'user', action: 'expireUser')
        patch "/api/user/update_profile_picture" (controller: 'user', action: 'updateProfilePicture')
        patch "/api/user/update_pan" (controller: 'user', action: 'updatePAN')
        post "/api/user/create_subscription_order/$subscriptionType" (controller: 'user', action: 'createSubscriptionOrder')
        post "/api/user/get_subscription_transactions" (controller: 'user', action: 'getSubscriptionTransactions')
        post "/api/user/create_course_order/$courseId/$branchId" (controller: 'user', action: 'createCourseOrder')
        post "/api/user/get_course_transactions" (controller: 'user', action: 'getCourseTransactions')
        post "/api/user/get_coin_transactions" (controller: 'user', action: 'getUserTransactions')
        //post "/api/admin/user_delete/$id" (controller: 'admin', action: 'deleteUser')
        post "/api/webhook/razorpay" (controller: 'razorpay', action: 'paymentWebhook')
        get "/api/rewards" (controller: 'reward', action: 'getRewards')
        post "/api/rewards/$rewardId" (controller: 'reward', action: 'redeemReward')
        post "/api/rewards/history" (controller: 'reward', action: 'getRedemptionHistory')
        post "/api/subscribe" (controller: 'razorpay', action: 'subscribe')
        get "/api/user/fcm" (controller: 'user', action: 'getUserFCM')



        //admin url

        post "/api/admin/get_users" (controller: 'admin', action: 'getUsers')
        get "/api/admin/dashboard_stats" (controller: 'admin', action: 'getDashboardStats')
        post "/api/admin/revenue_stats" (controller: 'admin', action: 'getRevenueStats')
        post "/api/admin/enable_user/$id" (controller: 'admin', action: 'enableUser')
        post "/api/admin/disable_user/$id" (controller: 'admin', action: 'disableUser')
        post "/api/admin/get_reward_redemption" (controller: 'reward', action: 'getRedemptionDetails')
        post "/api/admin/update_redemption_status" (controller: 'reward', action: 'updateRedemptionStatus')
        post "/api/admin/credit_fund" (controller: 'admin', action: 'creditFundToUserWallet')
        post "/api/admin/debit_fund" (controller: 'admin', action: 'debitFundFromUserWallet')
        post "/api/admin/notify_user" (controller: 'admin', action: 'notifyUser')
        post "/api/admin/notify_topic" (controller: 'admin', action: 'notifyTopic')
        post "/api/admin/stock/upload" (controller: 'admin', action: 'uploadStockData')
        post "/api/admin/nifty_50_stock/upload" (controller: 'admin', action: 'uploadNifty50Stocks')
        post "/api/admin/nifty_FNO_stock/upload" (controller: 'admin', action: 'uploadNiftyFNOStocks')
        post "/api/admin/etf/upload" (controller: 'admin', action: 'uploadEtfData')
        post "/api/admin/holiday/upload" (controller: 'admin', action: 'uploadHolidayData')
        post "/api/admin/get_course_transactions" (controller: 'admin', action: 'getCourseTransactions')
        post "/api/admin/course/status" (controller: 'admin', action: 'updateCourseStatus')


        //admin stock recommendation
        post "/api/admin/stock/recommend" (controller: 'stock', action: 'createStockRecommendation')
        patch "/api/admin/stock/recommend/$id" (controller: 'stock', action: 'updateStockRecommendation')
        patch "/api/admin/stock/recommend/book/$id/$price" (controller: 'stock', action: 'bookStockRecommendation')
        delete "/api/admin/stock/recommend/$id" (controller: 'stock', action: 'deleteStockRecommendation')

        post "/api/admin/stock/recommend/get" (controller: 'stock', action: 'getStockRecommendations')

        //admin stock portfolio
        post "/api/admin/portfolio/$stockSymbol" (controller: 'stock', action: 'createPortfolioStock')
        delete "/api/admin/portfolio/$id" (controller: 'stock', action: 'deletePortfolioStock')

        get "/api/portfolio" (controller: 'stock', action: 'getStockPortfolio')
        post "/api/history/portfolio" (controller: 'stock', action: 'getPortfolioHistory')

        get "/api/ipo" (controller: 'stock', action: 'getIPOData')
        post "/api/fii" (controller: 'stock', action: 'getFIIData')






        //courses & branches
        get "/api/branch" (controller: 'registration', action: 'getBranches')
        get "/api/course" (controller: 'registration', action: 'getCourses')


        //admin blog
        post "/api/blog" (controller: 'blog', action: 'createBlog')
        patch "/api/blog/$blogId" (controller: 'blog', action: 'updateBlog')
        delete "/api/blog/$blogId" (controller: 'blog', action: 'deleteBlog')
        delete "/api/blog/comment/admin/$blogCommentId" (controller: 'blog', action: 'deleteBlogComment')

        //user blog
        post "/api/blog/comment" (controller: 'blog', action: 'createBlogComment')
        patch "/api/blog/comment/$blogCommentId" (controller: 'blog', action: 'updateBlogComment')
        delete "/api/blog/comment/$blogCommentId" (controller: 'blog', action: 'deleteBlogCommentByUser')
        post "/api/blog/get" (controller: 'blog', action: 'getBlogs')
        post "/api/blog/comment/get" (controller: 'blog', action: 'getBlogComments')

        // stock

        get "/api/stock/$query" (controller: 'stock', action: 'searchStock')
        get "/api/etf/$query" (controller: 'stock', action: 'searchEtf')
        get "/api/market/holiday" (controller: 'stock', action: 'getHolidayList')

        //workshop
        post "/api/workshop/register" (controller: 'user', action: 'registerToWorkshop')
        get "/api/workshop/register" (controller: 'user', action: 'getWorkshopRegistration')
        post "/api/admin/workshop" (controller: 'admin', action: 'getWorkshopRegistrations')



        //demat enquiry
        post "/api/demat/addEnquiry" (controller: 'dematEnquiry', action: 'addEnquiry')
        post "/api/admin/demat/getEnquiries" (controller: 'admin', action: 'getDematEnquiries')
        post "/api/admin/demat/updateEnquiries" (controller: 'admin', action: 'updateDematEnquiryStatus')




        "/"(controller: 'application', action:'index')
        "500"(view: '/error')
        "404"(view: '/notFound')
    }
}
