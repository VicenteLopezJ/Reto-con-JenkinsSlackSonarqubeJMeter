package vallegrande.edu.pe.service;

import org.junit.jupiter.api.Test;
import vallegrande.edu.pe.model.Product;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ProductServiceTest {

    private final ProductService service = new ProductService();

    @Test
    void getProductsDevuelveCincoProductos() {
        List<Product> products = service.getProducts();
        assertEquals(5, products.size());
        assertEquals("Laptop", products.get(0).getName());
    }

    @Test
    void processProductConNombre() {
        assertEquals("Producto procesado: Mouse", service.processProduct("Mouse"));
    }

    @Test
    void processProductVacio() {
        assertEquals("Producto vacío", service.processProduct(""));
    }

    @Test
    void processProductNulo() {
        assertEquals("Producto no válido", service.processProduct(null));
    }

    @Test
    void validateProductValido() {
        assertTrue(service.validateProduct(new Product(1, "Laptop", 2500.00)));
    }

    @Test
    void validateProductInvalido() {
        assertFalse(service.validateProduct(null));
        assertFalse(service.validateProduct(new Product(1, null, 10.0)));
        assertFalse(service.validateProduct(new Product(1, "", 10.0)));
        assertFalse(service.validateProduct(new Product(1, "Mouse", null)));
        assertFalse(service.validateProduct(new Product(1, "Mouse", 0.0)));
    }
}
