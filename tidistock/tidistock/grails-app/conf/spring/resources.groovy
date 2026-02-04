import tidistock.UserPasswordEncoderListener
import tidistock.CustomRestAuthenticationFailureHandler
import javax.servlet.http.HttpServletResponse

// Place your Spring DSL code here
beans = {
    userPasswordEncoderListener(UserPasswordEncoderListener)
}

beans = {
    restAuthenticationFailureHandler(CustomRestAuthenticationFailureHandler) {
        statusCode = HttpServletResponse.SC_UNAUTHORIZED
    }
}
