--- 1.
CREATE PROCEDURE NEW_JOB (
    p_job_id    IN VARCHAR,
    p_job_title IN VARCHAR,
    p_min_salary IN NUMERIC
)
    LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO JOBS (JOB_ID, JOB_TITLE, MIN_SALARY, MAX_SALARY)
    VALUES (p_job_id, p_job_title, p_min_salary, p_min_salary * 2);
END;
$$;

CALL NEW_JOB('SY_ANAL2', 'System Analyst', 6000);

--- 2.
CREATE OR REPLACE PROCEDURE ADD_JOB_HIST(
    p_emp_id   INT,
    p_new_job_id VARCHAR
)
    LANGUAGE plpgsql
AS $$
DECLARE
    v_hire_date DATE;
    v_min_salary NUMERIC;
BEGIN
    -- Проверяем существование сотрудника
    SELECT hire_date INTO v_hire_date
    FROM EMPLOYEES
    WHERE employee_id = p_emp_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Employee with ID % does not exist.', p_emp_id;
    END IF;

    -- Получаем минимальную зарплату для новой должности
    SELECT min_salary INTO v_min_salary
    FROM JOBS
    WHERE job_id = p_new_job_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Job ID % does not exist.', p_new_job_id;
    END IF;

    -- Добавляем запись в JOB_HISTORY
    INSERT INTO JOB_HISTORY (EMPLOYEE_ID, JOB_ID, START_DATE, END_DATE)
    VALUES (p_emp_id, (SELECT job_id FROM EMPLOYEES WHERE employee_id = p_emp_id), v_hire_date, CURRENT_DATE);

    -- Обновляем EMPLOYEES: новую должность, новую дату приёма на работу, новую зарплату
    UPDATE EMPLOYEES
    SET job_id = p_new_job_id,
        hire_date = CURRENT_DATE,
        salary = v_min_salary + 500
    WHERE employee_id = p_emp_id;
END;
$$;

ALTER TABLE EMPLOYEES DISABLE TRIGGER ALL;
ALTER TABLE JOBS DISABLE TRIGGER ALL;
ALTER TABLE JOB_HISTORY DISABLE TRIGGER ALL;

CALL ADD_JOB_HIST(106, 'SY_ANAL');

SELECT * FROM JOB_HISTORY WHERE EMPLOYEE_ID = 106;

SELECT * FROM EMPLOYEES WHERE EMPLOYEE_ID = 106;

ALTER TABLE EMPLOYEES ENABLE TRIGGER ALL;
ALTER TABLE JOBS ENABLE TRIGGER ALL;
ALTER TABLE JOB_HISTORY ENABLE TRIGGER ALL;

COMMIT;

--- 3.
CREATE OR REPLACE PROCEDURE UPD_JOBSAL(
    p_job_id      VARCHAR,
    p_min_salary  NUMERIC,
    p_max_salary  NUMERIC
)
    LANGUAGE plpgsql
AS $$
BEGIN
    -- Проверяем, что job_id существует
    IF NOT EXISTS (SELECT 1 FROM JOBS WHERE JOB_ID = p_job_id) THEN
        RAISE EXCEPTION 'Job ID % does not exist.', p_job_id;
    END IF;

    -- Проверяем, что максимальная зарплата больше минимальной
    IF p_max_salary < p_min_salary THEN
        RAISE EXCEPTION 'Maximum salary % cannot be less than minimum salary %.', p_max_salary, p_min_salary;
    END IF;

    -- Попытка обновления записи
    BEGIN
        UPDATE JOBS
        SET MIN_SALARY = p_min_salary,
            MAX_SALARY = p_max_salary
        WHERE JOB_ID = p_job_id;
    EXCEPTION
        WHEN SQLSTATE '55P03' THEN -- Код ошибки "resource locked"
            RAISE NOTICE 'The row for job ID % is currently locked by another transaction.', p_job_id;
    END;
END;
$$;

ALTER TABLE EMPLOYEES DISABLE TRIGGER ALL;
ALTER TABLE JOBS DISABLE TRIGGER ALL;

CALL UPD_JOBSAL('SY_ANAL', 7000, 140);

CALL UPD_JOBSAL('SY_ANAL', 7000, 14000);

SELECT * FROM JOBS WHERE JOB_ID = 'SY_ANAL';

ALTER TABLE EMPLOYEES ENABLE TRIGGER ALL;
ALTER TABLE JOBS ENABLE TRIGGER ALL;

COMMIT;

--- 4.
CREATE OR REPLACE FUNCTION GET_YEARS_SERVICE(p_employee_id INT)
    RETURNS NUMERIC
    LANGUAGE plpgsql
AS $$
DECLARE
    v_years_service NUMERIC := 0;
    v_hire_date DATE;
BEGIN
    -- Проверяем, существует ли указанный employee_id
    SELECT HIRE_DATE
    INTO v_hire_date
    FROM EMPLOYEES
    WHERE EMPLOYEE_ID = p_employee_id;

    -- Если hire_date отсутствует, выбрасываем исключение
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Employee ID % does not exist.', p_employee_id;
    END IF;

    -- Вычисляем количество лет службы
    SELECT EXTRACT(YEAR FROM AGE(CURRENT_DATE, v_hire_date)) INTO v_years_service;

    RETURN v_years_service;

EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'An error occurred: %', SQLERRM;
        RETURN NULL; -- Возвращаем NULL в случае ошибки
END;
$$;

DO $$
    BEGIN
        RAISE NOTICE 'Years of service for employee 999: %', GET_YEARS_SERVICE(999);
    END;
$$;

DO $$
    BEGIN
        RAISE NOTICE 'Years of service for employee 106: %', GET_YEARS_SERVICE(106);
    END;
$$;

--- 5.
CREATE OR REPLACE FUNCTION GET_JOB_COUNT (p_emp_id INT)
    RETURNS INT AS $$
DECLARE
    job_count INT;
BEGIN
    -- Получаем количество различных должностей
    SELECT COUNT(DISTINCT job_id)
    INTO job_count
    FROM job_history
    WHERE employee_id = p_emp_id;

    -- Проверяем, если сотрудник не найден
    IF job_count IS NULL THEN
        RAISE EXCEPTION 'Employee ID % not found', p_emp_id;
    END IF;

    RETURN job_count;
END;
$$ LANGUAGE plpgsql;


DO $$
    BEGIN
        RAISE NOTICE 'Number of different jobs for employee 176: %', GET_JOB_COUNT(176);
    END;
$$;

--- 6.
CREATE OR REPLACE FUNCTION check_salary_range()
    RETURNS TRIGGER AS $$
DECLARE
    emp_count INT;
BEGIN
    -- Проверяем, если изменяются минимальная или максимальная зарплата
    IF NEW.min_salary <> OLD.min_salary OR NEW.max_salary <> OLD.max_salary THEN
        -- Проверяем, есть ли сотрудники, чьи зарплаты выходят за новый диапазон
        SELECT COUNT(*)
        INTO emp_count
        FROM employees
        WHERE job_id = NEW.job_id
          AND (salary < NEW.min_salary OR salary > NEW.max_salary);

        -- Если есть такие сотрудники, выбрасываем исключение
        IF emp_count > 0 THEN
            RAISE EXCEPTION 'Salary change violates range for existing employees with job ID %', NEW.job_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE TRIGGER CHECK_SAL_RANGE
    BEFORE UPDATE ON jobs
    FOR EACH ROW
EXECUTE FUNCTION check_salary_range();

SELECT job_id, min_salary, max_salary
FROM jobs
WHERE job_id = 'SY_ANAL';

UPDATE jobs
SET min_salary = 5000, max_salary = 7000
WHERE job_id = 'SY_ANAL';

SELECT job_id, min_salary, max_salary
FROM jobs
WHERE job_id = 'SY_ANAL';

UPDATE jobs
SET min_salary = 7000, max_salary = 18000
WHERE job_id = 'SY_ANAL';

SELECT job_id, min_salary, max_salary
FROM jobs
WHERE job_id = 'SY_ANAL';









