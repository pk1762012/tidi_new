package tidistock

import tidistock.enums.OrderType
import tidistock.enums.SubscriptionType
import tidistock.requestbody.CourseStatusUpdatePayload
import tidistock.requestbody.CourseTransactionPayload
import tidistock.requestbody.DematEnquiryUpdatePayload
import tidistock.requestbody.GetDematEnquiryPayload
import tidistock.requestbody.GetUsersPayload
import tidistock.requestbody.NotificationPayload
import tidistock.requestbody.NotificationTopicPayload
import grails.gorm.PagedResultList
import grails.gorm.transactions.Transactional
import grails.plugin.springsecurity.annotation.Secured
import io.micronaut.http.HttpStatus
import tidistock.requestbody.PaginationPayload
import tidistock.requestbody.RevenueStatsPayload
import tidistock.requestbody.WorkshopGetPayload

import java.time.LocalDate
import java.time.ZoneId

@Transactional
@Secured('ROLE_ADMIN')
class AdminService {

    def messageSource
    def fireBaseService

    def deleteUser(String id) {
        User user = User.findById(id)
        if (!user) {
             return  [status: false, code: HttpStatus.NOT_FOUND.getCode(), message: messageSource.getMessage('user.doesNotExist', new Object[] { }, Locale.ENGLISH)]
        }
        UserRole.findAllByUser(user).each { UserRole userRole -> userRole.delete(flush : true)}
        user.wallet.delete(flush : true)
        user.delete(flush : true)
        return  [status: true, code: HttpStatus.OK.getCode(), message: messageSource.getMessage('user.delete.success', new Object[] { }, Locale.ENGLISH)]
    }

    def enableUser(String id) {
        User user = User.findById(id)
        if (!user) {
            return  [status: false, code: HttpStatus.NOT_FOUND.getCode(), message: messageSource.getMessage('user.doesNotExist', new Object[] { }, Locale.ENGLISH)]
        }
        user.enabled = true
        user.save(flush: true)
        return  [status: true, code: HttpStatus.OK.getCode(), message: messageSource.getMessage('user.enabled.success', new Object[] { }, Locale.ENGLISH)]
    }

    def disableUser(String id) {
        User user = User.findById(id)
        if (!user) {
            return  [status: false, code: HttpStatus.NOT_FOUND.getCode(), message: messageSource.getMessage('user.doesNotExist', new Object[] { }, Locale.ENGLISH)]
        }
        user.enabled = false
        user.save(flush: true)
        return  [status: true, code: HttpStatus.OK.getCode(), message: messageSource.getMessage('user.disabled.success', new Object[] { }, Locale.ENGLISH)]
    }

    def notifyUser(NotificationPayload payload) {
        User user = User.findById(payload.userId)
        if (!user) {
            return  [status: false, code: HttpStatus.NOT_FOUND.getCode(), message: messageSource.getMessage('user.doesNotExist', new Object[] { }, Locale.ENGLISH)]
        }
        if (user.fcmToken) {
            fireBaseService.sendToToken(user.fcmToken, payload.title, payload.body)
        }
        return  [status: true, code: HttpStatus.OK.getCode(), message: messageSource.getMessage('fcm.notification.sent', new Object[] { }, Locale.ENGLISH)]

    }

    def notifyTopic(NotificationTopicPayload payload) {
        fireBaseService.sendToTopic(payload.title, payload.body, payload.topic)
        return  [status: true, code: HttpStatus.OK.getCode(), message: messageSource.getMessage('fcm.notification.sent', new Object[] { }, Locale.ENGLISH)]
    }

    @Transactional(readOnly = true)
    def getWorkshopRegistrations(WorkshopGetPayload payload) {
        int limit = payload.limit ?: 10
        int offset = payload.offset ?: 0
        String sortField = "dateCreated"
        String sortOrder = "desc"

        def criteria = WorkshopRegistration.createCriteria()
        PagedResultList result = criteria.list(max: limit, offset: offset) {

            eq("orderType", OrderType.PAID)

            if (payload.date) {
                eq("date", payload.date)
            }

            if (payload.branchId) {
                branch {
                    eq("id", payload.branchId)
                }
            }

            order(sortField, sortOrder)
        } as PagedResultList

        def data = result.collect { WorkshopRegistration workshopRegistration ->
            [
                    id             : workshopRegistration.id,
                    username       : workshopRegistration.user.username,
                    firstName      : workshopRegistration.user.firstName,
                    lastName       : workshopRegistration.user.lastName,
                    date           : workshopRegistration.date,
                    branch         : workshopRegistration.branch.name,
                    branchId       : workshopRegistration.branch.id,
                    dateCreated    : workshopRegistration.dateCreated
            ]
        }

        return [
                limit     : limit,
                offset    : offset,
                totalCount: result.totalCount,
                data      : data
        ]
    }

    @Transactional(readOnly = true)
    def getUsers(GetUsersPayload getUsersPayload) {
        int limit = getUsersPayload.limit ?: 10
        int offset = getUsersPayload.offset ?: 0
        String sortField = getUsersPayload.sortField ?: "dateCreated"
        String sortOrder = getUsersPayload.sortOrder?.toLowerCase() == "asc" ? "asc" : "desc"
        String search = getUsersPayload.search?.trim()

        // Step 1: Get user IDs that have ROLE_USER
        def roleUserIds = UserRole.createCriteria().list {
            role {
                eq("authority", "ROLE_USER")
            }
            projections {
                property("user.id")
            }
        }

        if (!roleUserIds) {
            return [ limit: limit, offset: offset, totalCount: 0, data: [] ]
        }

        def criteria = User.createCriteria()
        PagedResultList result = criteria.list(max: limit, offset: offset) {
            'in'("id", roleUserIds)

            if (search) {
                or {
                    ilike("username", "%${search}%")
                    ilike("firstName", "%${search}%")
                    ilike("lastName", "%${search}%")
                }
            }

            if (sortField && sortOrder) {
                if (sortField == "balance") {
                    wallet {
                        order("balance", sortOrder)
                    }
                } else if (sortField == "isSubscribed") {
                    wallet {
                        subscription {
                            order("isSubscribed", sortOrder)
                        }
                    }
                } else if (sortField == "expirationDate") {
                    wallet {
                        subscription {
                            order("expirationDate", sortOrder)
                        }
                    }
                } else {
                    order(sortField, sortOrder)
                }
            }

        } as PagedResultList

        // Step 4: Map results
        def data = result.collect { User user ->
            [
                    id             : user?.id,
                    username       : user?.username,
                    firstName      : user?.firstName,
                    lastName       : user?.lastName,
                    balance        : user?.wallet?.balance ?: 0.0,
                    isSubscribed   : user?.wallet?.subscription?.isSubscribed ?: false,
                    expirationDate : user?.wallet?.subscription?.expirationDate,
                    enabled        : user?.enabled ?: false,
                    pan            : user?.pan,
                    email          : user?.email,
                    dateCreated    : user?.dateCreated
            ]
        }

        return [
                limit     : limit,
                offset    : offset,
                totalCount: result.totalCount,
                data      : data
        ]
    }


    @Transactional(readOnly = true)
    def getRevenueStats(RevenueStatsPayload payload) {

        Date startDate = payload.startDate ?
                Date.from(payload.startDate.atStartOfDay(ZoneId.systemDefault()).toInstant()) :
                null

        Date endDate = payload.endDate ?
                Date.from(payload.endDate.plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant()) :
                null

        // Subscription revenue
        BigDecimal subscriptionRevenue = getSubscriptionRevenue(startDate, endDate)

        // Branch-wise revenues
        def courseByBranch   = getCourseRevenueByBranch(startDate, endDate)
        def workshopByBranch = getWorkshopRevenueByBranch(startDate, endDate)

        // Branch-wise counts
        def courseCountByBranch   = getCourseCountByBranch(startDate, endDate)
        def workshopCountByBranch = getWorkshopCountByBranch(startDate, endDate)

        // Merge branch-wise revenue + counts
        def branchWiseRevenue = mergeBranchRevenueWithCounts(
                courseByBranch, workshopByBranch, courseCountByBranch, workshopCountByBranch
        )

        // Total branch revenue
        BigDecimal totalBranchRevenue =
                branchWiseRevenue.values().sum { it.totalRevenue } ?: 0

        // Total course/workshop revenue (global sums)
        BigDecimal totalCourseRevenue   = getTotalCourseRevenue(startDate, endDate)
        BigDecimal totalWorkshopRevenue = getTotalWorkshopRevenue(startDate, endDate)

        // Overall revenue (subscription + branches)
        BigDecimal overallRevenue =
                subscriptionRevenue + totalBranchRevenue

        // Overall counts
        Long totalCourseCount   = getTotalCourseCount(startDate, endDate)
        Long totalWorkshopCount = getTotalWorkshopCount(startDate, endDate)

        return [
                subscriptionRevenue : subscriptionRevenue,
                totalCourseRevenue  : totalCourseRevenue,
                totalWorkshopRevenue: totalWorkshopRevenue,
                totalCourseCount    : totalCourseCount,
                totalWorkshopCount  : totalWorkshopCount,
                branchWiseRevenue   : branchWiseRevenue.values().toList(),
                totalBranchRevenue  : totalBranchRevenue,
                overallRevenue      : overallRevenue
        ]
    }

    private BigDecimal getSubscriptionRevenue(Date startDate, Date endDate) {
        SubscriptionOrder.createCriteria().get {
            eq("orderType", OrderType.PAID)
            if (startDate) ge("dateCreated", startDate)
            if (endDate)   lt("dateCreated", endDate)
            projections { sum("amount") }
        } ?: BigDecimal.ZERO
    }

    private BigDecimal getTotalCourseRevenue(Date startDate, Date endDate) {
        CourseOrder.createCriteria().get {
            eq("orderType", OrderType.PAID)
            if (startDate) ge("dateCreated", startDate)
            if (endDate)   lt("dateCreated", endDate)
            projections { sum("amount") }
        } ?: BigDecimal.ZERO
    }

    private BigDecimal getTotalWorkshopRevenue(Date startDate, Date endDate) {
        WorkshopRegistration.createCriteria().get {
            eq("orderType", OrderType.PAID)
            if (startDate) ge("dateCreated", startDate)
            if (endDate)   lt("dateCreated", endDate)
            projections { sum("amount") }
        } ?: BigDecimal.ZERO
    }

    private List<Map> getCourseRevenueByBranch(Date startDate, Date endDate) {
        CourseOrder.createCriteria().list {
            eq("orderType", OrderType.PAID)
            if (startDate) ge("dateCreated", startDate)
            if (endDate)   lt("dateCreated", endDate)

            createAlias("branch", "branch")

            projections {
                groupProperty("branch.id")
                groupProperty("branch.name")
                sum("amount")
            }
        }.collect {
            [
                    branchId     : it[0],
                    branchName   : it[1],
                    courseRevenue: it[2] ?: BigDecimal.ZERO
            ]
        }
    }

    private List<Map> getWorkshopRevenueByBranch(Date startDate, Date endDate) {
        WorkshopRegistration.createCriteria().list {
            eq("orderType", OrderType.PAID)
            if (startDate) ge("dateCreated", startDate)
            if (endDate)   lt("dateCreated", endDate)

            createAlias("branch", "branch")

            projections {
                groupProperty("branch.id")
                groupProperty("branch.name")
                sum("amount")
            }
        }.collect {
            [
                    branchId       : it[0],
                    branchName     : it[1],
                    workshopRevenue: it[2] ?: BigDecimal.ZERO
            ]
        }
    }

    private List<Map> getCourseCountByBranch(Date startDate, Date endDate) {
        CourseOrder.createCriteria().list {
            eq("orderType", OrderType.PAID)
            if (startDate) ge("dateCreated", startDate)
            if (endDate)   lt("dateCreated", endDate)

            createAlias("branch", "branch")

            projections {
                groupProperty("branch.id")
                groupProperty("branch.name")
                count("id")
            }
        }.collect {
            [
                    branchId   : it[0],
                    branchName : it[1],
                    courseCount: it[2] ?: 0L
            ]
        }
    }

    private List<Map> getWorkshopCountByBranch(Date startDate, Date endDate) {
        WorkshopRegistration.createCriteria().list {
            eq("orderType", OrderType.PAID)
            if (startDate) ge("dateCreated", startDate)
            if (endDate)   lt("dateCreated", endDate)

            createAlias("branch", "branch")

            projections {
                groupProperty("branch.id")
                groupProperty("branch.name")
                count("id")
            }
        }.collect {
            [
                    branchId      : it[0],
                    branchName    : it[1],
                    workshopCount : it[2] ?: 0L
            ]
        }
    }

    private Map<String, Map> mergeBranchRevenueWithCounts(List courses, List workshops, List courseCounts, List workshopCounts) {
        Map<String, Map> result = [:]

        // Merge revenues
        [courses, workshops].eachWithIndex { list, index ->
            list.each { row ->
                def branch = result[row.branchId] ?: [
                        branchId       : row.branchId,
                        branchName     : row.branchName,
                        courseRevenue  : BigDecimal.ZERO,
                        workshopRevenue: BigDecimal.ZERO,
                        courseCount    : 0L,
                        workshopCount  : 0L,
                        totalRevenue   : BigDecimal.ZERO
                ]
                if (index == 0) branch.courseRevenue = row.courseRevenue
                if (index == 1) branch.workshopRevenue = row.workshopRevenue
                branch.totalRevenue = branch.courseRevenue + branch.workshopRevenue
                result[row.branchId] = branch
            }
        }

        // Merge counts
        [courseCounts, workshopCounts].eachWithIndex { list, index ->
            list.each { row ->
                def branch = result[row.branchId] ?: [
                        branchId       : row.branchId,
                        branchName     : row.branchName,
                        courseRevenue  : BigDecimal.ZERO,
                        workshopRevenue: BigDecimal.ZERO,
                        courseCount    : 0L,
                        workshopCount  : 0L,
                        totalRevenue   : BigDecimal.ZERO
                ]
                if (index == 0) branch.courseCount = row.courseCount
                if (index == 1) branch.workshopCount = row.workshopCount
                result[row.branchId] = branch
            }
        }

        return result
    }

    private Long getTotalCourseCount(Date startDate, Date endDate) {
        CourseOrder.createCriteria().get {
            eq("orderType", OrderType.PAID)
            if (startDate) ge("dateCreated", startDate)
            if (endDate)   lt("dateCreated", endDate)
            projections { count("id") }
        } ?: 0L
    }

    private Long getTotalWorkshopCount(Date startDate, Date endDate) {
        WorkshopRegistration.createCriteria().get {
            eq("orderType", OrderType.PAID)
            if (startDate) ge("dateCreated", startDate)
            if (endDate)   lt("dateCreated", endDate)
            projections { count("id") }
        } ?: 0L
    }

    @Transactional(readOnly = true)
    def getDashboardStats() {
        def roleUserIds = UserRole.createCriteria().list {
            role {
                eq("authority", "ROLE_USER")
            }
            projections {
                property("user.id")
            }
        }

        if (!roleUserIds) {
            return [
                    activeUsers: 0,
                    subscribed: [
                            total: 0,
                            monthly: 0,
                            sixMonths: 0,
                            annual: 0
                    ]
            ]
        }

        // Active users count
        def activeUserCount = User.createCriteria().get {
            'in'("id", roleUserIds)
            eq("enabled", true)
            projections {
                countDistinct("id")
            }
        } ?: 0

        def now = new Date()

        def totalSubs = Subscription.createCriteria().get {
            eq("isSubscribed", true)
            ge("expirationDate", now)
            projections {
                countDistinct("id")
            }
        } ?: 0

        // Monthly subscriptions
        def monthlyCount = Subscription.createCriteria().get {
            eq("isSubscribed", true)
            eq("subscriptionType", SubscriptionType.MONTHLY)
            projections {
                countDistinct("id")
            }
        } ?: 0

        // 6 months subscriptions
        def sixMonthsCount = Subscription.createCriteria().get {
            eq("isSubscribed", true)
            eq("subscriptionType", SubscriptionType.HALF_YEARLY)
            projections {
                countDistinct("id")
            }
        } ?: 0

        // Annual subscriptions
        def annualCount = Subscription.createCriteria().get {
            eq("isSubscribed", true)
            eq("subscriptionType", SubscriptionType.YEARLY)
            projections {
                countDistinct("id")
            }
        } ?: 0

        return [
                activeUsers: activeUserCount,
                subscribed: [
                        total: totalSubs,
                        monthly: monthlyCount,
                        sixMonths: sixMonthsCount,
                        annual: annualCount
                ]
        ]
    }

    @Transactional(readOnly = true)
    def getCourseTransactions(CourseTransactionPayload payload) {
        int limit = payload.limit ?: 10
        int offset = payload.offset ?: 0
        String sortField = payload.sortField ?: "dateCreated"
        String sortOrder = payload.sortOrder?.toLowerCase() == "asc" ? "asc" : "desc"
        String search = payload.search?.trim()

        def criteria = CourseOrder.createCriteria()
        PagedResultList result = criteria.list(max: limit, offset: offset) {
            eq("orderType", OrderType.PAID)

            if (payload.status) {
                eq("status", payload.status)
            }
            if (search) {
                user {
                    or {
                        ilike("username", "%${search}%")
                        ilike("firstName", "%${search}%")
                        ilike("lastName", "%${search}%")
                    }
                }
            }

            if (payload.branchId) {
                branch {
                    eq("id", payload.branchId)
                }
            }

            if (sortField && sortOrder) {
                order(sortField, sortOrder)
            }

        } as PagedResultList

        def data = result.collect { CourseOrder courseOrder ->
            [
                    id             : courseOrder.id,
                    username       : courseOrder.user.username,
                    firstName      : courseOrder.user.firstName,
                    lastName       : courseOrder.user.lastName,
                    userId         : courseOrder.user.id,
                    dateCreated    : courseOrder?.dateCreated,
                    status         : courseOrder?.status,
                    branch         : courseOrder.branch.name,
                    branchId       : courseOrder.branch.id
            ]
        }

        return [
                limit     : limit,
                offset    : offset,
                totalCount: result.totalCount,
                data      : data
        ]
    }

    def updateCourseStatus(CourseStatusUpdatePayload payload) {
        CourseOrder courseOrder = CourseOrder.findById(payload.id)
        if (!courseOrder) {
            return  [status: false, code: HttpStatus.NOT_FOUND.getCode(), message: messageSource.getMessage('course.not.exist', new Object[] { }, Locale.ENGLISH)]
        }
        courseOrder.setStatus(payload.status)
        courseOrder.save(flush : true)
        return  [status: true, code: HttpStatus.OK.getCode(), message: messageSource.getMessage('course.status.update.success', new Object[] { }, Locale.ENGLISH)]
    }

    def updateDematEnquiryStatus(DematEnquiryUpdatePayload payload) {
        DematEnquiry dematEnquiry = DematEnquiry.findById(payload.id)
        if (!dematEnquiry) {
            return  [status: false, code: HttpStatus.NOT_FOUND.getCode(), message: messageSource.getMessage('demat.enquiry.not.exist', new Object[] { }, Locale.ENGLISH)]
        }
        dematEnquiry.setStatus(payload.status)
        dematEnquiry.setRemarks(payload.remarks)
        dematEnquiry.save(flush : true)
        return  [status: true, code: HttpStatus.OK.getCode(), message: messageSource.getMessage('demat.enquiry.status.update.success', new Object[] { }, Locale.ENGLISH)]
    }

    @Transactional(readOnly = true)
    def getDematEnquiries(GetDematEnquiryPayload payload) {
        int limit = payload.limit ?: 10
        int offset = payload.offset ?: 0
        String sortField = "dateCreated"
        String sortOrder = "desc"
        String search = payload.search?.trim()
        LocalDate date = payload.date


        def criteria = DematEnquiry.createCriteria()
        PagedResultList result = criteria.list(max: limit, offset: offset) {

            if (payload.status) {
                eq("status", payload.status)

            }

            if (search) {
                or {
                    ilike("phoneNumber", "%${search}%")
                    ilike("firstName", "%${search}%")
                    ilike("lastName", "%${search}%")
                }
            }

            if (date) {
                Date startOfDay = Date.from(date.atStartOfDay(ZoneId.systemDefault()).toInstant())
                Date endOfDay = Date.from(date.plusDays(1).atStartOfDay(ZoneId.systemDefault()).toInstant())
                between("dateCreated", startOfDay, endOfDay)
            }

            if (sortField && sortOrder) {
                order(sortField, sortOrder)
            }

        } as PagedResultList

        def data = result.collect { DematEnquiry dematEnquiry ->
            [
                    id             : dematEnquiry.id,
                    phoneNumber    : dematEnquiry.phoneNumber,
                    firstName      : dematEnquiry.firstName,
                    lastName       : dematEnquiry.lastName,
                    dateCreated    : dematEnquiry.dateCreated,
                    status         : dematEnquiry.status,
                    remarks        : dematEnquiry.remarks

            ]
        }

        return [
                limit     : limit,
                offset    : offset,
                totalCount: result.totalCount,
                data      : data
        ]
    }

}
