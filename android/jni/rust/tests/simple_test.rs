#[cfg(test)]
mod tests {
    #[test]
    fn test_basic() {
        assert_eq!(1 + 1, 2);
    }

    #[test]
    fn test_string() {
        let s = "hello";
        assert_eq!(s.len(), 5);
    }

    #[test]
    fn test_arrays() {
        let arr = [1, 2, 3];
        assert_eq!(arr[0], 1);
        assert_eq!(arr.len(), 3);
    }
}
