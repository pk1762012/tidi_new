package tidistock

import grails.util.Holders
import groovy.json.JsonBuilder
import groovy.transform.CompileStatic
import groovy.util.logging.Slf4j
import org.springframework.security.authentication.*
import org.springframework.security.core.AuthenticationException
import org.springframework.security.web.authentication.AuthenticationFailureHandler

import javax.servlet.ServletException
import javax.servlet.http.HttpServletRequest
import javax.servlet.http.HttpServletResponse

@Slf4j
@CompileStatic
class CustomRestAuthenticationFailureHandler implements AuthenticationFailureHandler {

    /**
     * Configurable status code, by default: conf.rest.login.failureStatusCode?:HttpServletResponse.SC_FORBIDDEN
     */
    Integer statusCode

    /**
     * Called when an authentication attempt fails.
     * @param request the request during which the authentication attempt occurred.
     * @param response the response.
     * @param exception the exception which was thrown to reject the authentication request.
     */
    void onAuthenticationFailure(HttpServletRequest request, HttpServletResponse response, AuthenticationException exception) throws IOException, ServletException {
        response.setStatus(statusCode)
        response.addHeader('WWW-Authenticate', Holders.config.get("grails.plugin.springsecurity.rest.token.validation.headerName").toString())
        def errorMessage
        if (exception instanceof AccountExpiredException) {
            errorMessage = "Account is deleted"
        } else if (exception instanceof CredentialsExpiredException) {
            errorMessage = "Password is expired"
        } else if (exception instanceof DisabledException) {
            errorMessage = "Account is disabled"
        } else if (exception instanceof LockedException) {
            errorMessage = "Account is locked"
        } else if (exception instanceof BadCredentialsException) {
            errorMessage = "Username and Password are not matching"
        } else {
            errorMessage = "Authentication failed"
        }
        PrintWriter out = response.getWriter()
        response.setContentType("aplication/json")
        response.setCharacterEncoding("UTF-8");
        out.print(new JsonBuilder([code: statusCode,  status:false,message: errorMessage ]).toString());
        out.flush();
    }
}